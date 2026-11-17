import Foundation
import Testing
@testable import NotchKit

@Suite("Bluetooth headphone battery")
struct HeadphoneBatteryTests {
    @Test func matchesConnectedHeadsetAndUsesLowerEarbud() throws {
        let data = Data(#"{"SPBluetoothDataType":[{"device_connected":[{"Headset":{"device_batteryLevelLeft":"82%","device_batteryLevelRight":"61%","device_batteryLevelCase":"100%"}},{"Other":{"device_batteryLevelMain":"99%"}}],"device_not_connected":[{"Disconnected":{"device_batteryLevelMain":"70%"}}]}]}"#.utf8)
        #expect(HeadphoneBatteryReader.percentage(in: data, named: "headset") == 61)
        #expect(HeadphoneBatteryReader.percentage(in: data, named: "Disconnected") == nil)
        #expect(HeadphoneBatteryReader.percentage(in: data, named: "Missing") == nil)
    }
    @Test func keepsZeroAndRejectsInvalidOrCaseOnlyBattery() {
        for (value, expected) in [("0%", 0 as Int?), ("101%", nil), ("Unknown", nil)] {
            let data = Data("{\"SPBluetoothDataType\":[{\"device_connected\":[{\"Headset\":{\"device_batteryLevelMain\":\"\(value)\",\"device_batteryLevelCase\":\"90%\"}}]}]}".utf8)
            #expect(HeadphoneBatteryReader.percentage(in: data, named: "Headset") == expected)
        }
        #expect(HeadphoneBatteryReader.percentage(in: Data("invalid".utf8), named: "Headset") == nil)
    }
}
