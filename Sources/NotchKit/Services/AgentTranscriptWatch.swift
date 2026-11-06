import Foundation

/// Notices when a Claude Code permission request shown in the notch was answered in Claude
/// Code's own window instead. Claude Code doesn't stop our hook then, so the notch would keep
/// asking. While the request waits, this reads the new lines of that session's transcript (the
/// file Claude Code names in the request) about twice a second, only on this Mac, looking for the
/// result of the tool call being asked about. Nothing is kept or sent.
final class AgentTranscriptWatch: @unchecked Sendable {
    private let url: URL
    private let onAnswered: @Sendable () -> Void
    private let queue = DispatchQueue(label: "DynamicLedge.agent-transcript", qos: .utility)
    // Confined to `queue`.
    private var scan: AgentTranscriptScan
    private var offset: UInt64 = 0
    private var partial = Data()
    private var timer: DispatchSourceTimer?
    private var started = false

    /// How much of the end of the transcript is read at first, to find the tool call.
    static let tail: UInt64 = 512 * 1024
    static let interval: DispatchTimeInterval = .milliseconds(500)

    /// Nil when the request doesn't name a transcript or a tool.
    init?(hookInput data: Data, onAnswered: @escaping @Sendable () -> Void) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = object["transcript_path"] as? String, path.hasSuffix(".jsonl"),
              let tool = object["tool_name"] as? String, !tool.isEmpty else { return nil }
        url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        scan = AgentTranscriptScan(toolName: tool, toolInput: object["tool_input"] as? [String: Any] ?? [:])
        self.onAnswered = onAnswered
    }

    func start() {
        queue.async { [self] in
            guard !started else { return }
            started = true
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            offset = size > Self.tail ? size - Self.tail : 0
            // Starting mid-file: the first line is cut, so it's skipped.
            let skipsFirstLine = offset > 0
            // What's already there only says which calls exist: earlier runs of the same command
            // have their results too, and those mustn't count as an answer.
            readNewLines(skippingFirst: skipsFirstLine, reports: false)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + Self.interval, repeating: Self.interval, leeway: .milliseconds(200))
            timer.setEventHandler { [weak self] in self?.readNewLines(skippingFirst: false, reports: true) }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    private func readNewLines(skippingFirst: Bool, reports: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        guard size > offset else {
            // Replaced or cut short: start again from the end.
            if size < offset { offset = size; partial.removeAll() }
            return
        }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.read(upToCount: Int(size - offset)) else { return }
        offset += UInt64(data.count)
        partial.append(data)
        var lines = partial.split(separator: 0x0A, omittingEmptySubsequences: false)
        partial = Data(lines.removeLast())
        if skippingFirst, !lines.isEmpty { lines.removeFirst() }
        for line in lines where scan.consume(Data(line)) && reports {
            timer?.cancel()
            timer = nil
            onAnswered()
            return
        }
    }
}

/// Follows a transcript line by line: finds the newest call of the asked-about tool with the
/// same input that has no result yet, then reports when its result arrives.
struct AgentTranscriptScan {
    let toolName: String
    let toolInput: NSDictionary
    /// Calls of this tool with this input, oldest first, and whether each has a result.
    private var calls: [(id: String, answered: Bool)] = []

    init(toolName: String, toolInput: [String: Any]) {
        self.toolName = toolName
        self.toolInput = toolInput as NSDictionary
    }

    /// The call being asked about: the newest matching one still waiting for its result.
    var waitingCall: String? {
        calls.last.flatMap { $0.answered ? nil : $0.id }
    }

    /// Reads one line. True once the call being asked about has its result.
    mutating func consume(_ line: Data) -> Bool {
        // Cheap checks first: most lines are neither.
        let mentionsCall = line.range(of: Data("\"tool_use\"".utf8)) != nil
        let mentionsResult = line.range(of: Data("\"tool_result\"".utf8)) != nil
        guard mentionsCall || mentionsResult,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return false }
        for item in content {
            switch item["type"] as? String {
            case "tool_use":
                let input = NSDictionary(dictionary: item["input"] as? [String: Any] ?? [:])
                guard item["name"] as? String == toolName, let id = item["id"] as? String, input.isEqual(toolInput) else { continue }
                calls.append((id, false))
            case "tool_result":
                guard let id = item["tool_use_id"] as? String,
                      let index = calls.firstIndex(where: { $0.id == id }) else { continue }
                let wasWaiting = index == calls.count - 1 && !calls[index].answered
                calls[index].answered = true
                if wasWaiting { return true }
            default:
                continue
            }
        }
        return false
    }
}
