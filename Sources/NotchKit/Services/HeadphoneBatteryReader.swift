import Foundation

/// Reads only connected Bluetooth devices; unsupported or absent values stay unknown.
enum HeadphoneBatteryReader {
    static func percentage(in data: Data, named name: String) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = root["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        for controller in controllers {
            for device in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (deviceName, raw) in device where normalized(deviceName) == normalized(name) {
                    guard let properties = raw as? [String: Any] else { continue }
                    func value(_ key: String) -> Int? {
                        guard let raw = properties[key] as? String,
                              let value = Int(raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)),
                              (0...100).contains(value) else { return nil }
                        return value
                    }
                    if let main = value("device_batteryLevelMain") { return main }
                    return [value("device_batteryLevelLeft"), value("device_batteryLevelRight")].compactMap { $0 }.min()
                }
            }
        }
        return nil
    }

    private static func normalized(_ name: String) -> String {
        name.replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func read(named name: String) async -> Int? {
        await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "mini"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                let pid = process.processIdentifier
                let deadline = DispatchWorkItem { _ = kill(pid, SIGKILL) }
                DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: deadline)
                defer { deadline.cancel() }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0, data.count <= 2 * 1024 * 1024 else { return nil }
                return percentage(in: data, named: name)
            } catch { return nil }
        }.value
    }
}
