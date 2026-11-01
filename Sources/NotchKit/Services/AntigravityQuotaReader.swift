import Foundation

/// Reads the running app's loopback service. Credentials never leave this Mac.
enum AntigravityQuotaReader {
    static func read() async -> AIProviderUsage? {
        let connection = await Task.detached(priority: .utility) { discover() }.value
        guard let connection else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 2
        let session = URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        for port in connection.ports {
            guard let url = URL(string: "http://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/RetrieveUserQuotaSummary") else { continue }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(connection.token, forHTTPHeaderField: "X-Codeium-Csrf-Token")
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let usage = parse(data) else { continue }
            return usage
        }
        return nil
    }

    static func parse(_ data: Data) -> AIProviderUsage? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = root["response"] as? [String: Any],
              let groups = response["groups"] as? [[String: Any]] else { return nil }
        var windows: [AIUsageWindow] = []
        for group in groups {
            guard let name = group["displayName"] as? String,
                  let buckets = group["buckets"] as? [[String: Any]] else { continue }
            for bucket in buckets {
                guard let fraction = bucket["remainingFraction"] as? NSNumber,
                      CFGetTypeID(fraction) != CFBooleanGetTypeID(),
                      fraction.doubleValue.isFinite, (0...1).contains(fraction.doubleValue),
                      let window = bucket["window"] as? String else { continue }
                let label = window == "5h" ? "5-hour limit" : window == "weekly" ? "Weekly limit" : window
                let reset = (bucket["resetTime"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
                windows.append(AIUsageWindow(name: "\(name) · \(label)", usedPercent: (1 - fraction.doubleValue) * 100,
                                             resetsAt: reset, sourceDescription: "Antigravity shared model-family quota"))
            }
        }
        guard !windows.isEmpty else { return nil }
        return AIProviderUsage(provider: .antigravity, status: .active, plan: "Shared model-family limits",
                               windows: windows, lastUpdated: Date(), attribution: "Antigravity local quota service")
    }

    private struct Connection: Sendable { let token: String; let ports: [Int] }

    private static func discover() -> Connection? {
        guard let output = run("/bin/ps", ["-axo", "pid=,command="]) else { return nil }
        for line in output.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count > 3, let pid = Int(parts[0]),
                  line.contains("/Applications/Antigravity.app/Contents/Resources/bin/language_server "),
                  let index = parts.firstIndex(of: "--csrf_token"), index + 1 < parts.count,
                  let sockets = run("/usr/sbin/lsof", ["-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN", "-Fn"]) else { continue }
            let ports = sockets.split(separator: "\n").compactMap { line -> Int? in
                guard line.hasPrefix("n127.0.0.1:"), let part = line.split(separator: ":").last,
                      let port = Int(part), (1...65535).contains(port) else { return nil }
                return port
            }
            return Connection(token: parts[index + 1], ports: ports)
        }
        return nil
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
}
