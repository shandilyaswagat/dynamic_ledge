import Foundation
import Testing
@testable import NotchKit

@Suite("Usage history and estimates")
struct AIUsageHistoryTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func cumulativeReportsAreCountedOnceAndSplitByDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = calendar.startOfDay(for: now)
        var parser = CodexTokenHistoryReader.Parser(cutoff: today.addingTimeInterval(-86400), now: now, calendar: calendar)
        func event(_ date: Date, _ input: Int, _ output: Int, _ cached: Int) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["type": "event_msg", "timestamp": ISO8601DateFormatter().string(from: date),
                "payload": ["type": "token_count", "info": ["total_token_usage": ["input_tokens": input, "output_tokens": output, "cached_input_tokens": cached]]]])
        }
        parser.consume(try event(today.addingTimeInterval(-100), 100, 10, 20))
        parser.consume(try event(today.addingTimeInterval(100), 160, 30, 30))
        parser.consume(try event(today.addingTimeInterval(101), 160, 30, 30))
        #expect(parser.days[today]?.total == 80)
        #expect(parser.days[today]?.cached == 10)
        #expect(parser.days[today.addingTimeInterval(-86400)]?.total == 110)
        #expect(!parser.isPartial)
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
