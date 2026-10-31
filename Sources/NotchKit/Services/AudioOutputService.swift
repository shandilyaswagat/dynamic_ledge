import CoreAudio
import Foundation
import Observation

public struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    public let id: AudioDeviceID
    public let name: String
    public let isDefault: Bool
    public let isBluetooth: Bool

    public init(id: AudioDeviceID, name: String, isDefault: Bool, isBluetooth: Bool) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.isBluetooth = isBluetooth
    }

    public var symbol: String {
        if isBluetooth {
            return HeadphoneSymbol.symbol(forDeviceName: name)
        }
        return "speaker.wave.2.fill"
    }
}

@MainActor
@Observable
public final class AudioOutputService {
    public private(set) var devices: [AudioOutputDevice] = []
    public private(set) var currentDevice: AudioOutputDevice?

    @ObservationIgnored private var deviceListener: AudioHW.Listener?
    @ObservationIgnored private var defaultListener: AudioHW.Listener?
    @ObservationIgnored private let listProvider: @MainActor () -> [AudioOutputDevice]
    @ObservationIgnored private let setter: (AudioDeviceID) -> Bool

    public init(
        listProvider: (@MainActor () -> [AudioOutputDevice])? = nil,
        setter: ((AudioDeviceID) -> Bool)? = nil
    ) {
        self.listProvider = listProvider ?? AudioOutputService.liveDevices
        self.setter = setter ?? { AudioHW.setDefaultOutputDevice($0) }
        refresh()
    }

    public static func liveDevices() -> [AudioOutputDevice] {
        let currentID = AudioHW.defaultOutputDevice()
        return AudioHW.outputDevices().compactMap { id in
            guard let name = AudioHW.deviceName(id), !name.isEmpty else { return nil }
            return AudioOutputDevice(
                id: id,
                name: name,
                isDefault: id == currentID,
                isBluetooth: AudioHW.isBluetooth(id)
            )
        }
    }

    public func start() {
        guard deviceListener == nil else { return }
        refresh()
        deviceListener = AudioHW.listen(AudioHW.system, AudioHW.address(kAudioHardwarePropertyDevices)) { [weak self] in
            self?.refresh()
        }
        defaultListener = AudioHW.listen(AudioHW.system, AudioHW.address(kAudioHardwarePropertyDefaultOutputDevice)) { [weak self] in
            self?.refresh()
        }
    }

    public func stop() {
        deviceListener?.remove(); deviceListener = nil
        defaultListener?.remove(); defaultListener = nil
    }

    public func refresh() {
        devices = listProvider()
        currentDevice = devices.first { $0.isDefault }
    }

    @discardableResult
    public func selectDevice(_ device: AudioOutputDevice) -> Bool {
        let success = setter(device.id)
        if success {
            refresh()
        }
        return success
    }
}
