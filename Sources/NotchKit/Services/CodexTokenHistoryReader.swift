import Foundation

/// Bounded scan of local session usage events. No sign-in files are opened or text retained.
enum CodexTokenHistoryReader {
    static func read(now: Date = Date()) async -> AITokenHistory {
        await Task.detached(priority: .utility) {
            let root = ProcessInfo.processInfo.environment["CODEX_HOME"].map {
                URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath)
            } ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
            return scan(root: root.appendingPathComponent("sessions"), now: now)
        }.value
    }

    static func scan(root: URL, now: Date) -> AITokenHistory {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else {
            return AITokenHistory(checkedAt: now)
        }
        var files: [(URL, Date)] = []
        var partial = false
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > 20_000 { partial = true; break }
            guard url.pathExtension == "jsonl", let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true,
                  let modified = values.contentModificationDate, modified >= cutoff else { continue }
            files.append((url, modified))
        }
        files.sort { $0.1 > $1.1 }
        if files.count > 200 { partial = true }
        var days: [Date: AIDailyTokens] = [:]
        var budget = 64 * 1024 * 1024
        for (url, _) in files.prefix(200) {
            guard budget > 0 else { partial = true; break }
            guard let file = try? FileHandle(forReadingFrom: url) else { partial = true; continue }
            var parser = Parser(cutoff: cutoff, now: now, calendar: calendar)
            var buffer = Data()
            var eof = false
            while budget > 0 {
                let chunk: Data
                do { chunk = try file.read(upToCount: min(65536, budget)) ?? Data() }
                catch { partial = true; break }
                if chunk.isEmpty { eof = true; break }
                budget -= chunk.count
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 10) {
                    parser.consume(Data(buffer[..<newline]))
                    buffer.removeSubrange(...newline)
                }
                if buffer.count > 4 * 1024 * 1024 { partial = true; break }
            }
            try? file.close()
            // Ignore an unfinished last line: the agent may still be writing it.
            if !eof { partial = true }
            for value in parser.days.values {
                var day = days[value.day] ?? AIDailyTokens(day: value.day)
                day.input += value.input; day.output += value.output; day.cached += value.cached
                days[value.day] = day
            }
            partial = partial || parser.isPartial
        }
        return AITokenHistory(days: days.values.sorted { $0.day < $1.day }, isPartial: partial, checkedAt: now)
    }

    struct Parser {
        let cutoff: Date
        let now: Date
        let calendar: Calendar
        var days: [Date: AIDailyTokens] = [:]
        var isPartial = false
        private var previous = (input: 0, output: 0, cached: 0)
        private let formatter = ISO8601DateFormatter()

        init(cutoff: Date, now: Date, calendar: Calendar) {
            self.cutoff = cutoff; self.now = now; self.calendar = calendar
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        }

        mutating func consume(_ line: Data) {
            guard line.range(of: Data("token_count".utf8)) != nil else { return }
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let totals = info["total_token_usage"] as? [String: Any] else { return }
            func count(_ key: String) -> Int? {
                guard let number = totals[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, number.doubleValue >= 0, number.doubleValue <= 1e12,
                      number.doubleValue.rounded(.down) == number.doubleValue else { return nil }
                return number.intValue
            }
            guard let input = count("input_tokens"), let output = count("output_tokens"),
                  let cached = count("cached_input_tokens"), cached <= input else { isPartial = true; return }
            // Repeated cumulative reports must not be counted twice.
            let delta = (input - previous.input, output - previous.output, cached - previous.cached)
            previous = (input, output, cached)
            guard delta.0 >= 0, delta.1 >= 0, delta.2 >= 0, delta.2 <= delta.0 else { isPartial = true; return }
            guard let timestamp = object["timestamp"] as? String,
                  let date = formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp) else { isPartial = true; return }
            guard date >= cutoff, date <= now else { return }
            let day = calendar.startOfDay(for: date)
            var entry = days[day] ?? AIDailyTokens(day: day)
            entry.input += delta.0; entry.output += delta.1; entry.cached += delta.2
            days[day] = entry
        }
    }
}
