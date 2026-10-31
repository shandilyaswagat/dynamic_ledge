import Foundation
import Testing
@testable import NotchKit

@MainActor
@Suite("Focus and AirPods alert features")
struct FocusAndAirPodsTests {
    @Test func focusMonitorEmitsAlert() {
        let monitor = FocusMonitor()
        var receivedAlert: IslandAlert?
        monitor.onAlert = { receivedAlert = $0 }

        monitor.notify(mode: FocusMode.dnd)
        #expect(receivedAlert == .focus(name: "Do Not Disturb", symbol: "moon.fill"))
        #expect(receivedAlert?.kind == .focus)
        #expect(receivedAlert?.displayDuration == 3)
    }

    @Test func airPodsAlertStatusProperties() {
        let battery = AirPodsBatteryStatus(left: 85, right: 90, caseBattery: 100)
        let alert = IslandAlert.airPods(
            name: "Pritam’s AirPods Pro",
            symbol: "airpodspro",
            battery: battery,
            mode: .noiseCancellation
        )
        #expect(alert.kind == .headphones)
        #expect(alert.displayDuration == 4)

        #expect(AirPodsListeningMode.noiseCancellation.symbol == "ear.and.waveform")
        #expect(AirPodsListeningMode.transparency.symbol == "ambient.light")
    }
}
