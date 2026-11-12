import Foundation
import os

/// Bounded scan of local session usage events. No sign-in files are opened or text retained.
enum CodexTokenHistoryReader {
    /// One request's tokens. `key` (its time and running totals) spots the same event copied into
    /// another session file, as a forked or resumed session does, so it's counted once.
    struct Event: Equatable, Sendable {
        let key: String
        let date: Date
        let input: Int
        let output: Int
        let cached: Int
    }

    private struct ReadFile: Sendable {
        let size: Int
        let modified: Date
        let events: [Event]
        let isPartial: Bool
    }

    /// Files already read, by path, so a refresh only reads the ones that changed. In memory only.
    private static let files = OSAllocatedUnfairLock<[String: ReadFile]>(initialState: [:])

    static func forgetFiles() {
        files.withLock { $0.removeAll() }
    }

    static func read(now: Date = Date()) async -> AITokenHistory {
        await Task.detached(priority: .utility) {
            let root = ProcessInfo.processInfo.environment["CODEX_HOME"].map {
                URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath)
            } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
            return scan(root: root.appendingPathComponent("sessions"), now: now)
        }.value
    }

    static func scan(root: URL, now: Date, calendar: Calendar = .current) -> AITokenHistory {
        let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
            return AITokenHistory(checkedAt: now)
        }
        var found: [(url: URL, size: Int, modified: Date)] = []
        var partial = false
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > 20_000 { partial = true; break }
            guard url.pathExtension == "jsonl", let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate, modified >= cutoff else { continue }
            found.append((url, values.fileSize ?? 0, modified))
        }
        found.sort { $0.modified > $1.modified }
        if found.count > 200 { partial = true }

        let known = files.withLock { $0 }
        var current: [String: ReadFile] = [:]
        var events: [Event] = []
        var budget = 64 * 1024 * 1024
        for file in found.prefix(200) {
            let path = file.url.path
            if let cached = known[path], cached.size == file.size, cached.modified == file.modified {
                current[path] = cached
            } else if budget > 0, let read = readFile(file.url, budget: &budget) {
                let entry = ReadFile(size: file.size, modified: file.modified, events: read.events, isPartial: read.isPartial)
                current[path] = entry
            } else {
                partial = true
                continue
            }
            events += current[path]!.events
            partial = partial || current[path]!.isPartial
        }
        // Keep only complete reads; a cut-short file is read again next time.
        let complete = current.filter { !$0.value.isPartial }
        files.withLock { $0 = complete }
        return AITokenHistory(days: days(from: events, cutoff: cutoff, now: now, calendar: calendar), isPartial: partial, checkedAt: now)
    }

    /// Daily totals, counting an event copied into several files once.
    static func days(from events: [Event], cutoff: Date, now: Date, calendar: Calendar) -> [AIDailyTokens] {
        var seen = Set<String>()
        var days: [Date: AIDailyTokens] = [:]
        for event in events where event.date >= cutoff && event.date <= now && seen.insert(event.key).inserted {
            let day = calendar.startOfDay(for: event.date)
            var entry = days[day] ?? AIDailyTokens(day: day)
            entry.input += event.input; entry.output += event.output; entry.cached += event.cached
            days[day] = entry
        }
        return days.values.sorted { $0.day < $1.day }
    }

    private static func readFile(_ url: URL, budget: inout Int) -> (events: [Event], isPartial: Bool)? {
        guard let file = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? file.close() }
        var parser = Parser()
        var buffer = Data()
        var partial = false
        var eof = false
        while budget > 0 {
            let chunk: Data
            do { chunk = try file.read(upToCount: min(65536, budget)) ?? Data() }
            catch { partial = true; break }
            if chunk.isEmpty { eof = true; break }
            budget -= chunk.count
            buffer.append(chunk)
            var start = buffer.startIndex
            while let newline = buffer[start...].firstIndex(of: 10) {
                parser.consume(buffer[start..<newline])
                start = buffer.index(after: newline)
            }
            buffer.removeSubrange(..<start)
            if buffer.count > 4 * 1024 * 1024 { partial = true; break }
        }
        // An unfinished last line is left out: the agent may still be writing it.
        return (parser.events, partial || !eof || parser.isPartial)
    }

    struct Parser {
        var events: [Event] = []
        var isPartial = false
        private var previous: Totals?
        private let formatter = ISO8601DateFormatter()

        struct Totals: Equatable {
            var input = 0, output = 0, cached = 0
        }

        init() {
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        }

        mutating func consume(_ line: Data) {
            guard line.range(of: Data("token_count".utf8)) != nil else { return }
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any] else { return }
            guard let totals = Self.totals(info["total_token_usage"]) else { isPartial = true; return }
            // The same running totals again is a repeated report, not a new request.
            guard totals != previous else { return }
            defer { previous = totals }
            // The request's own count, which a forked session's first report also has right. Without
            // it, the change since the last report.
            let amount: Totals
            if let last = Self.totals(info["last_token_usage"]),
               last.input <= totals.input, last.output <= totals.output, last.cached <= totals.cached {
                amount = last
            } else if let previous, totals.input >= previous.input, totals.output >= previous.output, totals.cached >= previous.cached {
                amount = Totals(input: totals.input - previous.input, output: totals.output - previous.output, cached: totals.cached - previous.cached)
            } else if previous == nil {
                amount = totals
            } else {
                isPartial = true
                return
            }
            guard let timestamp = object["timestamp"] as? String,
                  let date = formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp) else { isPartial = true; return }
            let key = "\(timestamp)|\(totals.input)|\(totals.output)|\(totals.cached)"
            events.append(Event(key: key, date: date, input: amount.input, output: amount.output, cached: amount.cached))
        }

        private static func totals(_ value: Any?) -> Totals? {
            guard let usage = value as? [String: Any] else { return nil }
            func count(_ key: String) -> Int? {
                guard let number = usage[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= 1e12,
                      number.doubleValue.rounded(.down) == number.doubleValue else { return nil }
                return number.intValue
            }
            guard let input = count("input_tokens"), let output = count("output_tokens"),
                  let cached = count("cached_input_tokens"), cached <= input else { return nil }
            return Totals(input: input, output: output, cached: cached)
        }
    }
}
