import CoreAudio
import Foundation
import Testing
@testable import NotchKit

@MainActor
@Suite("Audio output picker")
struct AudioOutputTests {
    @Test func enumeratesDevicesAndIdentifiesDefault() {
        let mockDevices = [
            AudioOutputDevice(id: 1, name: "MacBook Pro Speakers", isDefault: false, isBluetooth: false),
            AudioOutputDevice(id: 2, name: "AirPods Pro", isDefault: true, isBluetooth: true)
        ]
        var selectedID: AudioDeviceID?
        let service = AudioOutputService(
            listProvider: { mockDevices },
            setter: { id in
                selectedID = id
                return true
            }
        )

        #expect(service.devices.count == 2)
        #expect(service.currentDevice?.id == 2)
        #expect(service.currentDevice?.name == "AirPods Pro")
        #expect(service.currentDevice?.symbol == "airpodspro")

        let speaker = service.devices[0]
        #expect(speaker.symbol == "speaker.wave.2.fill")
        let success = service.selectDevice(speaker)
        #expect(success)
        #expect(selectedID == 1)
    }

    @Test func handlesFailedSelectionGracefully() {
        let mockDevices = [
            AudioOutputDevice(id: 1, name: "External Headphones", isDefault: true, isBluetooth: false)
        ]
        let service = AudioOutputService(
            listProvider: { mockDevices },
            setter: { _ in false }
        )

        #expect(service.currentDevice?.id == 1)
        let success = service.selectDevice(mockDevices[0])
        #expect(!success)
    }
}
