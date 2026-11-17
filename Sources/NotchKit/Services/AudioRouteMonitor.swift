import CoreAudio
import Foundation

/// Reports when Bluetooth headphones become the sound output, like the iPhone's AirPods alert.
@MainActor
public final class AudioRouteMonitor {
    public var onAlert: ((IslandAlert) -> Void)?

    private var currentDevice: AudioDeviceID = 0
    private var listener: AudioHW.Listener?
    private var batteryTask: Task<Void, Never>?
    /// AirPods re-register when they switch to the call profile; don't announce them twice.
    private var lastAnnounced: (name: String, date: Date)?

    public init() {}

    public func start() {
        guard listener == nil else { return }
        currentDevice = AudioHW.defaultOutputDevice()
        listener = AudioHW.listen(AudioHW.system, AudioHW.address(kAudioHardwarePropertyDefaultOutputDevice)) { [weak self] in
            self?.outputChanged()
        }
    }

    public func stop() {
        listener?.remove()
        listener = nil
        batteryTask?.cancel()
        batteryTask = nil
    }

    private func outputChanged() {
        let device = AudioHW.defaultOutputDevice()
        guard device != currentDevice else { return }
        currentDevice = device
        batteryTask?.cancel()
        guard AudioHW.isBluetooth(device), let name = AudioHW.deviceName(device) else { return }
        if let lastAnnounced, lastAnnounced.name == name, Date().timeIntervalSince(lastAnnounced.date) < 60 {
            return
        }
        lastAnnounced = (name, Date())
        batteryTask = Task { @MainActor [weak self] in
            let battery = await HeadphoneBatteryReader.read(named: name)
            guard !Task.isCancelled, let self, self.currentDevice == device else { return }
            self.onAlert?(.headphones(name: name, symbol: HeadphoneSymbol.symbol(forDeviceName: name), battery: battery))
        }
    }
}
