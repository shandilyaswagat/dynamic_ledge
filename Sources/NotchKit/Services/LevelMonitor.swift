import AppKit
import AudioToolbox
import CoreAudio

/// Reports volume and brightness changes so the notch can show them. Event-driven: Core Audio
/// listeners for volume, a DisplayServices callback for the built-in display's brightness, and
/// the brightness keys themselves, so that only a change you made with the keys is shown (as with
/// Apple's own indicator) and not one the display made on its own with automatic brightness.
@MainActor
public final class LevelMonitor {
    public var onChange: ((IslandAlert.LevelKind, Double, Bool) -> Void)?

    private var device: AudioDeviceID = 0
    private var deviceListener: AudioHW.Listener?
    private var volumeListeners: [AudioHW.Listener] = []
    private var lastVolume: (value: Double, muted: Bool)?
    private var lastBrightness: Double?
    private var brightnessRegistered = false
    private var isRunning = false
    private var keyMonitors: [Any] = []
    /// When a brightness key was last pressed, and whether the display answered it yet.
    private var lastBrightnessKey = Date.distantPast
    private var keyAnswered = true
    private var getBrightness: GetBrightness?
    private var brightnessDisplay: CGDirectDisplayID?

    /// Brightness keys move about 6 %; automatic brightness drifts in much smaller steps.
    nonisolated static let brightnessStep = 0.03
    /// A brightness change this soon after a brightness key was pressed was made with the key.
    /// The display answers within a few milliseconds; this leaves room for a busy Mac.
    nonisolated static let keyWindow: TimeInterval = 0.3

    public init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        deviceListener = AudioHW.listen(AudioHW.system, AudioHW.address(kAudioHardwarePropertyDefaultOutputDevice)) { [weak self] in
            self?.attachToOutput()
        }
        attachToOutput()
        registerBrightness()
        installKeyMonitors()
    }

    public func stop() {
        isRunning = false
        deviceListener?.remove()
        deviceListener = nil
        volumeListeners.forEach { $0.remove() }
        volumeListeners.removeAll()
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors.removeAll()
    }

    // MARK: Brightness keys

    /// The brightness keys are "system defined" events (subtype 8) carrying a key code in the
    /// high half of data1 (2 up, 3 down) and, in bits 8 to 15, 0xA for a press and 0xB for a
    /// release. Pure, so it can be tested.
    nonisolated static func isBrightnessKeyDown(subtype: Int16, data1: Int) -> Bool {
        guard subtype == 8 else { return false }
        let code = (data1 & 0xFFFF0000) >> 16
        let state = (data1 & 0xFF00) >> 8
        return (code == 2 || code == 3) && state == 0xA
    }

    /// Whether a brightness change at `now` was made with the keys, given when one was last pressed.
    nonisolated static func isKeyDriven(now: Date, lastKey: Date) -> Bool {
        let elapsed = now.timeIntervalSince(lastKey)
        return elapsed >= 0 && elapsed <= keyWindow
    }

    private func installKeyMonitors() {
        guard keyMonitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { [weak self] event in
            guard Self.isBrightnessKeyDown(subtype: event.subtype.rawValue, data1: event.data1) else { return }
            MainActor.assumeIsolated { self?.brightnessKeyPressed() }
        }
        // Global when another app is in front; local when this app is (the notch's own windows).
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined, handler: handler) {
            keyMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .systemDefined, handler: { event in
            handler(event)
            return event
        }) {
            keyMonitors.append(local)
        }
    }

    private func brightnessKeyPressed(at now: Date = Date()) {
        guard isRunning else { return }
        lastBrightnessKey = now
        keyAnswered = false
        // Normally the display answers within milliseconds and `brightnessChanged` shows it. At
        // the ends (already darkest or brightest) it doesn't change at all; Apple's indicator
        // still shows there, so show the level as it is.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, self.isRunning, !self.keyAnswered, let value = self.currentBrightness() else { return }
            self.keyAnswered = true
            self.lastBrightness = value
            self.onChange?(.brightness, value, false)
        }
    }

    private func currentBrightness() -> Double? {
        guard let get = getBrightness, let display = brightnessDisplay else { return nil }
        var value: Float = 0
        return get(display, &value) == 0 ? Double(value) : nil
    }

    // MARK: Volume

    private func attachToOutput() {
        volumeListeners.forEach { $0.remove() }
        volumeListeners.removeAll()
        device = AudioHW.defaultOutputDevice()
        // Switching devices isn't a volume change; start fresh from the new device's level.
        lastVolume = readVolume()
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            let address = AudioHW.address(selector, scope: kAudioDevicePropertyScopeOutput)
            if let listener = AudioHW.listen(device, address, handler: { [weak self] in self?.volumeChanged() }) {
                volumeListeners.append(listener)
            }
        }
    }

    private func readVolume() -> (value: Double, muted: Bool)? {
        let volumeAddress = AudioHW.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        let muteAddress = AudioHW.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        let volume: Float32 = AudioHW.value(device, volumeAddress, default: -1)
        guard volume >= 0 else { return nil }
        let muted: UInt32 = AudioHW.value(device, muteAddress, default: 0)
        return (Double(volume), muted != 0)
    }

    private func volumeChanged() {
        guard let reading = readVolume() else { return }
        defer { lastVolume = reading }
        guard let last = lastVolume, abs(last.value - reading.value) > 0.001 || last.muted != reading.muted else { return }
        onChange?(.volume, reading.value, reading.muted)
    }

    // MARK: Brightness

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias RegisterBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutableRawPointer?, CFNotificationCallback) -> Int32

    private static let displayServices = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)

    private static var builtInDisplay: CGDirectDisplayID? {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    private func registerBrightness() {
        guard !brightnessRegistered,
              let library = Self.displayServices,
              let getSymbol = dlsym(library, "DisplayServicesGetBrightness"),
              let registerSymbol = dlsym(library, "DisplayServicesRegisterForBrightnessChangeNotifications"),
              let display = Self.builtInDisplay
        else { return }
        let get = unsafeBitCast(getSymbol, to: GetBrightness.self)
        getBrightness = get
        brightnessDisplay = display
        var value: Float = 0
        if get(display, &value) == 0 {
            lastBrightness = Double(value)
        }
        let register = unsafeBitCast(registerSymbol, to: RegisterBrightness.self)
        LevelMonitor.current = self
        if register(display, nil, brightnessCallback) == 0 {
            brightnessRegistered = true
        }
    }

    /// The monitor that receives brightness callbacks; there is one per app.
    fileprivate static weak var current: LevelMonitor?

    func brightnessChanged(to value: Double, at now: Date = Date()) {
        guard isRunning else { return }
        let previous = lastBrightness
        lastBrightness = value
        guard !keyMonitors.isEmpty else {
            // No key events to go by: judge by the size of the step.
            if let previous, LevelMonitor.isUserBrightnessChange(from: previous, to: value) {
                onChange?(.brightness, value, false)
            }
            return
        }
        // Automatic brightness never presses a key, so it is never shown.
        guard LevelMonitor.isKeyDriven(now: now, lastKey: lastBrightnessKey) else { return }
        keyAnswered = true
        onChange?(.brightness, value, false)
    }

    /// Key presses jump; automatic brightness creeps. Only used when the keys can't be seen.
    nonisolated static func isUserBrightnessChange(from old: Double, to new: Double) -> Bool {
        abs(new - old) >= brightnessStep || (new <= 0.001 && old > 0.001) || (new >= 0.999 && old < 0.999)
    }
}

/// DisplayServices calls this when the built-in display's brightness changes. A plain global
/// function, so nothing about the caller's actor or thread is assumed.
private func brightnessCallback(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    let raw = (userInfo as NSDictionary?)?["value"]
    guard let value = (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap(Double.init) else { return }
    DispatchQueue.main.async {
        MainActor.assumeIsolated { LevelMonitor.current?.brightnessChanged(to: value) }
    }
}
