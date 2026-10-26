import AppKit
@preconcurrency import ApplicationServices
import CoreAudio
import CoreMediaIO
import Darwin
import Observation

/// Detects calls and other microphone use without any permission prompt.
@MainActor
@Observable
public final class CallMonitor {
    public struct Session: Equatable, Sendable {
        public var appName: String
        public var bundleIdentifier: String?
        public var processIdentifier: pid_t?
        public var startDate: Date
        public var usesCamera: Bool
        /// Known call app, or microphone plus camera (a video call in a browser, for example).
        public var isCall: Bool

        var key: String { bundleIdentifier ?? appName }
    }

    public private(set) var session: Session?
    public private(set) var appIcon: NSImage?

    /// Continuous use needed before the activity appears, so Siri and dictation don't flash it.
    static let startDelay: TimeInterval = 2
    /// Grace period before the activity ends, so a brief device switch doesn't restart the clock.
    static let endDelay: TimeInterval = 1.5

    @ObservationIgnored private var candidate: (key: String, since: Date)?
    @ObservationIgnored private var inactiveSince: Date?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var audioListeners: [AudioHW.Listener] = []
    @ObservationIgnored private var cameraListeners: [CameraListener] = []
    @ObservationIgnored private var isRunning = false

    public init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        installListeners()
        evaluate()
    }

    public func stop() {
        isRunning = false
        removeListeners()
        pollTask?.cancel()
        pollTask = nil
        session = nil
        appIcon = nil
        candidate = nil
    }

    public func showApp() {
        guard let pid = session?.processIdentifier, let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate()
    }

    /// The call app has a documented hang-up shortcut, so the notch can end the call for you.
    public var canHangUp: Bool {
        CallHangup.shortcut(for: session?.bundleIdentifier) != nil && session?.processIdentifier != nil
    }

    /// Sends the call app its own hang-up shortcut. Sending keys to another app needs
    /// Accessibility access; the first time, macOS asks for it and nothing is sent.
    @discardableResult
    public func hangUp() -> Bool {
        guard let session, let pid = session.processIdentifier,
              let shortcut = CallHangup.shortcut(for: session.bundleIdentifier) else { return false }
        guard AXIsProcessTrusted() else {
            DocumentWindowDrag.requestAccess()
            return false
        }
        // The shortcut goes to the app's meeting window, so bring it forward first.
        NSRunningApplication(processIdentifier: pid)?.activate()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            let source = CGEventSource(stateID: .hidSystemState)
            for isDown in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: isDown) else { continue }
                event.flags = shortcut.flags
                event.postToPid(pid)
            }
        }
        return true
    }

    // MARK: Listening

    private func installListeners() {
        removeListeners()
        let changed: @MainActor () -> Void = { [weak self] in self?.evaluate() }
        let reinstall: @MainActor () -> Void = { [weak self] in
            guard let self, self.isRunning else { return }
            self.installListeners()
            self.evaluate()
        }
        if let listener = AudioHW.listen(AudioHW.system, AudioHW.address(kAudioHardwarePropertyDevices), handler: reinstall) {
            audioListeners.append(listener)
        }
        if let listener = AudioHW.listen(AudioHW.system, AudioHW.address(kAudioHardwarePropertyProcessObjectList), handler: changed) {
            audioListeners.append(listener)
        }
        for device in AudioHW.inputDevices() {
            if let listener = AudioHW.listen(device, AudioHW.address(kAudioDevicePropertyDeviceIsRunningSomewhere), handler: changed) {
                audioListeners.append(listener)
            }
        }
        if let listener = CameraListener(object: CMIOObjectID(kCMIOObjectSystemObject), selector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices), handler: reinstall) {
            cameraListeners.append(listener)
        }
        for camera in Self.cameras() {
            if let listener = CameraListener(object: camera, selector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere), handler: changed) {
                cameraListeners.append(listener)
            }
        }
    }

    private func removeListeners() {
        audioListeners.forEach { $0.remove() }
        audioListeners.removeAll()
        cameraListeners.forEach { $0.remove() }
        cameraListeners.removeAll()
    }

    // MARK: Evaluation

    private struct MicUser {
        var app: NSRunningApplication?
        var bundleIdentifier: String?
        var pid: pid_t?
    }

    private func evaluate() {
        guard isRunning else { return }
        let now = Date()
        let users = Self.microphoneUsers()
        let cameraOn = Self.isAnyCameraRunning()

        guard let user = Self.preferred(users) else {
            candidate = nil
            if session != nil {
                let since = inactiveSince ?? now
                inactiveSince = since
                if now.timeIntervalSince(since) >= Self.endDelay {
                    session = nil
                    appIcon = nil
                    inactiveSince = nil
                }
            }
            schedulePoll(after: session != nil ? 1 : nil)
            return
        }
        inactiveSince = nil

        let name = user.app?.localizedName ?? String(localized: "Microphone")
        let identifier = user.app?.bundleIdentifier ?? user.bundleIdentifier
        let isCall = CallClassifier.isCallApp(identifier) || cameraOn
        let key = identifier ?? name

        if var current = session, current.key == key {
            current.usesCamera = cameraOn
            current.isCall = isCall
            if current != session {
                session = current
            }
        } else {
            if candidate?.key != key {
                candidate = (key, now)
            }
            if let candidate, now.timeIntervalSince(candidate.since) >= Self.startDelay {
                session = Session(
                    appName: name,
                    bundleIdentifier: identifier,
                    processIdentifier: user.app?.processIdentifier ?? user.pid,
                    startDate: candidate.since,
                    usesCamera: cameraOn,
                    isCall: isCall
                )
                appIcon = user.app?.icon
            }
        }
        // Quick checks while a call is starting; a slower heartbeat once it is established.
        let settled = session?.key == key
        schedulePoll(after: settled ? 3 : 1)
    }

    /// Listeners report device-level changes; a light poll while active catches app changes
    /// and finishes the start/end delays. `nil` stops polling.
    private func schedulePoll(after seconds: Double?) {
        guard let seconds else {
            pollTask?.cancel()
            pollTask = nil
            return
        }
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.pollTask = nil
            self.evaluate()
        }
    }

    private static func preferred(_ users: [MicUser]) -> MicUser? {
        users.first { CallClassifier.isCallApp($0.app?.bundleIdentifier ?? $0.bundleIdentifier) } ?? users.first
    }

    private static func microphoneUsers() -> [MicUser] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let processes = AudioHW.processesUsingInput() else {
            // Older systems can't name the process; fall back to "some app is listening".
            let anyRunning = AudioHW.inputDevices().contains { AudioHW.isRunningSomewhere($0) }
            return anyRunning ? [MicUser(app: nil, bundleIdentifier: nil, pid: nil)] : []
        }
        var seen = Set<pid_t>()
        var users: [MicUser] = []
        for process in processes where process.pid != ownPID {
            if CallClassifier.shouldIgnore(process.bundleIdentifier) { continue }
            guard let app = owningApp(of: process.pid) ?? appForHelper(process.bundleIdentifier) else { continue }
            if CallClassifier.shouldIgnore(app.bundleIdentifier) || app.processIdentifier == ownPID { continue }
            guard seen.insert(app.processIdentifier).inserted else { continue }
            users.append(MicUser(app: app, bundleIdentifier: app.bundleIdentifier, pid: app.processIdentifier))
        }
        return users
    }

    /// Last resort for helpers whose parent can't be found: "com.google.Chrome.helper" → Chrome.
    private static func appForHelper(_ bundleIdentifier: String?) -> NSRunningApplication? {
        guard let bundleIdentifier else { return nil }
        let appIdentifier = CallClassifier.appBundleIdentifier(forHelper: bundleIdentifier)
        guard appIdentifier != bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: appIdentifier)
            .first { $0.activationPolicy == .regular }
    }

    /// The user-facing app behind a helper process (browser tabs, WebKit, XPC services).
    private static func owningApp(of pid: pid_t) -> NSRunningApplication? {
        func regular(_ pid: pid_t) -> NSRunningApplication? {
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { return nil }
            return app
        }
        if let app = regular(pid) { return app }
        if let responsible = responsiblePID(pid), responsible != pid, let app = regular(responsible) { return app }
        var current = pid
        for _ in 0..<4 {
            guard let parent = parentPID(of: current), parent > 1 else { break }
            if let app = regular(parent) { return app }
            current = parent
        }
        return nil
    }

    private static let responsibilityFunction: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    private static func responsiblePID(_ pid: pid_t) -> pid_t? {
        guard let function = responsibilityFunction else { return nil }
        let result = function(pid)
        return result > 0 ? result : nil
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    // MARK: Camera

    private nonisolated static func cameraAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    private static func cameras() -> [CMIOObjectID] {
        var address = cameraAddress(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        let status = devices.withUnsafeMutableBytes { buffer in
            CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, buffer.baseAddress!)
        }
        guard status == noErr else { return [] }
        return Array(devices.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    private static func isAnyCameraRunning() -> Bool {
        cameras().contains { camera in
            var address = cameraAddress(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            var running: UInt32 = 0
            var used: UInt32 = 0
            let status = CMIOObjectGetPropertyData(camera, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running)
            return status == noErr && running != 0
        }
    }

    /// Same approach as `AudioHW.listen`: the function-pointer API, so removal really removes.
    private final class CameraListener {
        let object: CMIOObjectID
        let address: CMIOObjectPropertyAddress
        private var context: UnsafeMutableRawPointer?

        init?(object: CMIOObjectID, selector: CMIOObjectPropertySelector, handler: @escaping @MainActor () -> Void) {
            var address = CallMonitor.cameraAddress(selector)
            let pointer = Unmanaged.passRetained(ListenerContext(handler: handler)).toOpaque()
            guard CMIOObjectAddPropertyListener(object, &address, cameraListenerProc, pointer) == noErr else {
                Unmanaged<ListenerContext>.fromOpaque(pointer).release()
                return nil
            }
            self.object = object
            self.address = address
            context = pointer
        }

        func remove() {
            guard let context else { return }
            self.context = nil
            var address = address
            CMIOObjectRemovePropertyListener(object, &address, cameraListenerProc, context)
            Unmanaged<ListenerContext>.fromOpaque(context).release()
        }

        deinit { remove() }
    }

}

private func cameraListenerProc(
    _ object: CMIOObjectID,
    _ count: UInt32,
    _ addresses: UnsafePointer<CMIOObjectPropertyAddress>?,
    _ context: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let context else { return noErr }
    Unmanaged<ListenerContext>.fromOpaque(context).takeUnretainedValue().fire()
    return noErr
}
