import Foundation
import Observation

/// Lists and runs the user's Shortcuts through the system `shortcuts` command.
@MainActor
@Observable
public final class ShortcutsService {
    public private(set) var available: [String] = []
    public private(set) var isLoading = false
    /// Names currently running, so their buttons can show progress.
    public private(set) var running: Set<String> = []

    @ObservationIgnored public var onFinish: ((String, Bool) -> Void)?

    private nonisolated static let tool = URL(fileURLWithPath: "/usr/bin/shortcuts")

    public init() {}

    public var isSupported: Bool {
        FileManager.default.isExecutableFile(atPath: Self.tool.path)
    }

    /// Reads the user's shortcut names. Runs the command off the main thread.
    public func reload() {
        guard isSupported, !isLoading else { return }
        isLoading = true
        Task { [weak self] in
            let names = await Self.run(arguments: ["list"]).output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard let self else { return }
            self.available = Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            self.isLoading = false
        }
    }

    public func run(_ name: String) {
        guard isSupported, !running.contains(name) else { return }
        running.insert(name)
        Task { [weak self] in
            let result = await Self.run(arguments: ["run", name])
            guard let self else { return }
            self.running.remove(name)
            self.onFinish?(name, result.status == 0)
        }
    }

    private nonisolated static func run(arguments: [String]) async -> (status: Int32, output: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = tool
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, ""))
                return
            }
            // Read until the tool closes its output, then wait. Waiting first could hang for good:
            // a long list fills the pipe and the tool blocks until someone reads it.
            DispatchQueue.global(qos: .userInitiated).async {
                let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
                process.waitUntilExit()
                continuation.resume(returning: (process.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
        }
    }
}
