import Foundation

enum BluetoothDeviceKind: Equatable, Sendable {
    case headphones, speaker, mouse, trackpad, keyboard, controller, microphone, other

    init(reportedType: String?) {
        switch reportedType?.lowercased().filter(\.isLetter) {
        case "headphones", "headset", "handsfree", "wearableheadset": self = .headphones
        case "loudspeaker", "speaker", "portablespeaker": self = .speaker
        case "mouse", "pointingdevice": self = .mouse
        case "trackpad": self = .trackpad
        case "keyboard", "keyboardmouse", "keyboardpointingdevice": self = .keyboard
        case "gamepad", "gamecontroller", "joystick": self = .controller
        case "microphone": self = .microphone
        default: self = .other
        }
    }
}

struct BluetoothBatteryDevice: Equatable, Sendable {
    let name: String
    let kind: BluetoothDeviceKind
    let main: Int?
    let left: Int?
    let right: Int?
    let chargingCase: Int?
}

enum BluetoothBatterySnapshot: Equatable, Sendable {
    case unavailable
    case poweredOff
    case connected([BluetoothBatteryDevice])
}

enum BluetoothBatteryReader {
    private static let queryQueue = DispatchQueue(label: "com.rectircle.DynamicNotch.bluetooth", qos: .utility)

    static func read() async -> BluetoothBatterySnapshot {
        await withCheckedContinuation { continuation in
            queryQueue.async {
                continuation.resume(returning: readReport())
            }
        }
    }

    private static func readReport() -> BluetoothBatterySnapshot {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["-json", "-timeout", "5", "SPBluetoothDataType"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? parse(data) : .unavailable
        } catch {
            return .unavailable
        }
    }

    static func parse(_ data: Data) -> BluetoothBatterySnapshot {
        guard let report = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let controllers = report["SPBluetoothDataType"] as? [[String: Any]],
              let controller = controllers.first(where: { $0["controller_properties"] != nil }),
              let properties = controller["controller_properties"] as? [String: Any] else {
            return .unavailable
        }
        if properties["controller_state"] as? String == "attrib_off" { return .poweredOff }

        guard let reportedDevices = controller["device_connected"] else { return .connected([]) }
        guard let connected = reportedDevices as? [Any] else { return .unavailable }
        let groups = connected.compactMap { $0 as? [String: Any] }
        let devices = groups.flatMap { group in
            group.compactMap { name, value -> BluetoothBatteryDevice? in
                guard let details = value as? [String: Any] else { return nil }
                let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let defaultName = (details["device_defaultName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                return BluetoothBatteryDevice(
                    name: name.isEmpty ? (defaultName ?? "") : name,
                    kind: BluetoothDeviceKind(reportedType: details["device_minorType"] as? String),
                    main: percentage(details["device_batteryLevelMain"]),
                    left: percentage(details["device_batteryLevelLeft"]),
                    right: percentage(details["device_batteryLevelRight"]),
                    chargingCase: percentage(details["device_batteryLevelCase"])
                )
            }
        }
        if devices.isEmpty, !connected.isEmpty { return .unavailable }
        return .connected(devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    private static func percentage(_ value: Any?) -> Int? {
        guard let value = value as? String else { return nil }
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let level = Int(raw.hasSuffix("%") ? raw.dropLast() : raw[...]),
              (0...100).contains(level) else { return nil }
        return level
    }
}
