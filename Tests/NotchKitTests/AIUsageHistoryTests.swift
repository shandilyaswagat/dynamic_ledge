import Foundation
import Testing
@testable import NotchKit

@Suite("Usage history and estimates")
struct AIUsageHistoryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func event(_ date: Date, _ input: Int, _ output: Int, _ cached: Int, last: [Int]? = nil) throws -> Data {
        var info: [String: Any] = ["total_token_usage": ["input_tokens": input, "output_tokens": output, "cached_input_tokens": cached]]
        if let last { info["last_token_usage"] = ["input_tokens": last[0], "output_tokens": last[1], "cached_input_tokens": last[2]] }
        return try JSONSerialization.data(withJSONObject: ["type": "event_msg", "timestamp": ISO8601DateFormatter().string(from: date),
            "payload": ["type": "token_count", "info": info]])
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func cumulativeReportsAreCountedOnceAndSplitByDay() throws {
        let today = utc.startOfDay(for: now)
        var parser = CodexTokenHistoryReader.Parser()
        parser.consume(try event(today.addingTimeInterval(-100), 100, 10, 20))
        parser.consume(try event(today.addingTimeInterval(100), 160, 30, 30))
        parser.consume(try event(today.addingTimeInterval(101), 160, 30, 30))
        let days = CodexTokenHistoryReader.days(from: parser.events, cutoff: today.addingTimeInterval(-86400), now: now, calendar: utc)
        #expect(days.first { $0.day == today }?.total == 80)
        #expect(days.first { $0.day == today }?.cached == 10)
        #expect(days.first { $0.day == today.addingTimeInterval(-86400) }?.total == 110)
        #expect(!parser.isPartial)
    }

    @Test func aForkedSessionDoesNotCountItsParentAgain() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let current = Date()
        let start = current.addingTimeInterval(-600)
        let first = try event(start, 100, 10, 0, last: [100, 10, 0])
        let second = try event(start.addingTimeInterval(60), 250, 30, 50, last: [150, 20, 50])
        // The fork copies the parent's reports, then its own first request starts from the parent's totals.
        let forked = try event(start.addingTimeInterval(120), 300, 35, 50, last: [50, 5, 0])
        func lines(_ events: [Data]) -> Data { events.reduce(into: Data()) { $0 += $1 + Data("\n".utf8) } }
        try lines([first, second]).write(to: root.appendingPathComponent("parent.jsonl"))
        try lines([first, second, forked]).write(to: root.appendingPathComponent("fork.jsonl"))
        let result = CodexTokenHistoryReader.scan(root: root, now: current, calendar: utc)
        #expect(result.days.reduce(0) { $0 + $1.total } == 335)
        #expect(result.days.reduce(0) { $0 + $1.cached } == 50)
        #expect(!result.isPartial)
        // Unchanged files are read from memory next time, with the same totals.
        #expect(CodexTokenHistoryReader.scan(root: root, now: current, calendar: utc).days.reduce(0) { $0 + $1.total } == 335)
    }

    @Test func cacheIsNotChargedTwiceAndMissingRatesStayUnknown() {
        let tokens = AIDailyTokens(day: now, input: 1_000_000, output: 100_000, cached: 500_000)
        #expect(AICostRates().estimate(tokens) == nil)
        #expect(AICostRates(input: "2", output: "10", cached: "0.2").estimate(tokens) == 2.1)
        #expect(AICostRates(input: "2", output: "10").estimate(tokens) == nil)
        #expect(AICostRates(input: "nan", output: "10", cached: "0.2").estimate(tokens) == nil)
        #expect(AICostRates(input: "-1", output: "10", cached: "0.2").estimate(tokens) == nil)
    }

    @Test func samplesDeduplicatePruneAndDoNotInventReadings() {
        let usage = AIProviderUsage(provider: .codex, status: .active,
            windows: [AIUsageWindow(name: "Session", usedPercent: 25, sourceDescription: "Test")],
            lastUpdated: now, attribution: "Test")
        let old = AIQuotaSample(provider: .codex, date: now.addingTimeInterval(-8 * 86400), remaining: 90)
        let samples = AIUsageHistory.recording([usage, usage, .unconfigured(for: .antigravity)], into: [old], now: now)
        #expect(samples.count == 1)
        #expect(samples.first?.remaining == 75)
    }

    @Test func scanIgnoresOtherJSONAndNeverRequiresSignInFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{\"prompt\":\"ignored\"}\n".utf8).write(to: root.appendingPathComponent("session.jsonl"))
        let result = CodexTokenHistoryReader.scan(root: root, now: Date())
        #expect(result.days.isEmpty)
        #expect(!result.isPartial)
    }

    @MainActor @Test func historyIsOptInAndTurningOffErasesSamples() throws {
        let name = "UsageHistory-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let service = AIUsageService(defaults: defaults)
        #expect(!service.recordsHistory)
        service.recordsHistory = true
        defaults.set(try JSONEncoder().encode([AIQuotaSample(provider: .codex, date: Date(), remaining: 20)]), forKey: "aiUsage.quotaHistory")
        let restored = AIUsageService(defaults: defaults)
        #expect(restored.recordsHistory)
        #expect(restored.quotaHistory.count == 1)
        restored.recordsHistory = false
        #expect(restored.quotaHistory.isEmpty)
        #expect(defaults.data(forKey: "aiUsage.quotaHistory") == nil)
    }
}
