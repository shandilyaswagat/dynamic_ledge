import Foundation
import Testing
@testable import NotchKit

struct BluetoothBatteryTests {
    @Test func keepsConnectedDevicesAndAvailableBatteryLevels() {
        let report = """
        {"SPBluetoothDataType":[{
            "controller_properties":{"controller_state":"attrib_on"},
            "device_connected":[
                {"ATH-M20xBT ":{"device_minorType":"Headset","device_batteryLevelMain":"100%"}},
                {"AirPods":{"device_minorType":"Headphones","device_batteryLevelMain":"74%","device_batteryLevelLeft":"0%","device_batteryLevelRight":"74%","device_batteryLevelCase":"52%"}},
                {"Mouse":{"device_minorType":"Mouse","device_batteryLevelMain":"255%"}},
                {"Keyboard":{"device_minorType":"Keyboard"}},
                {" ":{"device_defaultName":"Accessory "}},
                {"Unreadable":null}
            ],
            "device_not_connected":[{"Other Headphones":{"device_batteryLevelMain":"80%"}}]
        }]}
        """

        #expect(BluetoothBatteryReader.parse(Data(report.utf8)) == .connected([
            BluetoothBatteryDevice(name: "Accessory", kind: .other, main: nil, left: nil, right: nil, chargingCase: nil),
            BluetoothBatteryDevice(name: "AirPods", kind: .headphones, main: 74, left: 0, right: 74, chargingCase: 52),
            BluetoothBatteryDevice(name: "ATH-M20xBT", kind: .headphones, main: 100, left: nil, right: nil, chargingCase: nil),
            BluetoothBatteryDevice(name: "Keyboard", kind: .keyboard, main: nil, left: nil, right: nil, chargingCase: nil),
            BluetoothBatteryDevice(name: "Mouse", kind: .mouse, main: nil, left: nil, right: nil, chargingCase: nil)
        ]))
    }

    @Test func distinguishesUnavailableOffAndEmptyReports() {
        let unavailable = #"{"SPBluetoothDataType":[{}]}"#
        let unreadableDevices = #"{"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"},"device_connected":[{"Unreadable":null}]}]}"#
        let off = #"{"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_off"}}]}"#
        let empty = #"{"SPBluetoothDataType":[{"controller_properties":{"controller_state":"attrib_on"}}]}"#

        #expect(BluetoothBatteryReader.parse(Data(unavailable.utf8)) == .unavailable)
        #expect(BluetoothBatteryReader.parse(Data(unreadableDevices.utf8)) == .unavailable)
        #expect(BluetoothBatteryReader.parse(Data(off.utf8)) == .poweredOff)
        #expect(BluetoothBatteryReader.parse(Data(empty.utf8)) == .connected([]))
    }
}
