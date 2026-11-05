import Foundation
import Darwin

/// Reads the signed-in Codex account through the local app-server protocol, without handling credentials.
enum CodexUsageReader {
    static func read() async -> AIProviderUsage {
        await Task.detached(priority: .utility) { readSync() }.value
    }

    private static func readSync() -> AIProviderUsage {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            home.appendingPathComponent(".codex/plugins/.plugin-appserver/codex-cli/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return unavailable("Codex CLI not found. Install and sign in to Codex to see subscription usage.")
        }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return unavailable("Couldn't start Codex CLI.") }
        defer {
            try? input.fileHandleForWriting.close()
            // Make sure it's gone: ask, then insist after a second.
            if process.isRunning {
                process.terminate()
                let deadline = Date().addingTimeInterval(1)
                while process.isRunning, Date() < deadline { usleep(20_000) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
            }
        }
        let requests: [[String: Any]] = [
            ["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "dynamic-ledge", "version": "1.0"]]],
            ["method": "initialized"],
            ["id": 2, "method": "account/rateLimits/read", "params": [:]],
        ]
        do {
            for request in requests {
                var bytes = try JSONSerialization.data(withJSONObject: request)
                bytes.append(10)
                try input.fileHandleForWriting.write(contentsOf: bytes)
            }
        } catch { return unavailable("Couldn't communicate with Codex CLI.") }
        let fd = output.fileHandleForReading.fileDescriptor
        let deadline = Date().addingTimeInterval(10)
        var buffer = Data()
        while Date() < deadline && buffer.count < 1_048_576 {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let timeout = Int32(max(1, min(1000, deadline.timeIntervalSinceNow * 1000)))
            let ready = poll(&descriptor, 1, timeout)
            if ready < 0 { break }
            if ready == 0 { continue }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count <= 0 { break }
            buffer.append(contentsOf: bytes.prefix(count))
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      message["id"] as? Int == 2 else { continue }
                return parseResponse(message)
            }
        }
        return unavailable("Codex didn't return usage. Check your sign-in and try again.")
    }

    static func parseResponse(_ message: [String: Any]) -> AIProviderUsage {
        guard let result = message["result"] as? [String: Any],
              let limits = result["rateLimits"] as? [String: Any] else {
            return unavailable("Codex couldn't provide subscription usage. Check your sign-in.")
        }
        var windows: [AIUsageWindow] = []
        for (key, fallback) in [("primary", "Primary limit"), ("secondary", "Secondary limit")] {
            guard let window = limits[key] as? [String: Any],
                  let number = window["usedPercent"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID(),
                  case let used = number.doubleValue, used.isFinite, (0...100).contains(used) else { continue }
            let duration = window["windowDurationMins"] as? Int
            let name: String
            switch duration {
            case 300: name = "5-hour limit"
            case 10080: name = "Weekly limit"
            case let value?: name = "\(value)-minute limit"
            case nil: name = fallback
            }
            let resetNumber = window["resetsAt"] as? NSNumber
            let reset = resetNumber.map { Date(timeIntervalSince1970: $0.doubleValue) }
            windows.append(AIUsageWindow(name: name, usedPercent: used, resetsAt: reset,
                                         sourceDescription: "Codex CLI account limits"))
        }
        guard !windows.isEmpty else { return unavailable("Codex returned no subscription limits for this account.") }
        let plan = (limits["planType"] as? String)?.capitalized
        return AIProviderUsage(provider: .codex, status: .active, plan: plan,
                               windows: windows, lastUpdated: Date(), attribution: "Shared plan limits · Codex CLI")
    }

    private static func unavailable(_ message: String) -> AIProviderUsage {
        AIProviderUsage(provider: .codex, status: .unavailable(message), attribution: "Codex CLI")
    }
}
