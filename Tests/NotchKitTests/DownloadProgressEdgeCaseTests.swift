import Foundation
import Testing
@testable import NotchKit

@Suite("Download progress edge cases")
struct DownloadProgressEdgeCaseTests {
    @Test func summaryHandlesLargeByteCounts() throws {
        let now = Date()
        let summary = DownloadSummary([
            DownloadProgressItem(id: "a", name: "a", completed: Int64.max / 2, total: Int64.max, startedAt: now),
            DownloadProgressItem(id: "b", name: "b", completed: Int64.max / 2, total: Int64.max, startedAt: now),
        ])
        #expect(abs(try #require(summary.fraction) - 0.5) < 0.000_001)
    }

    @Test func negativeProgressDoesNotCancelOtherDownloads() {
        let now = Date()
        let summary = DownloadSummary([
            DownloadProgressItem(id: "a", name: "a", completed: -100, total: 100, startedAt: now),
            DownloadProgressItem(id: "b", name: "b", completed: 100, total: 100, startedAt: now),
        ])
        #expect(summary.fraction == 0.5)
    }

    @Test func frequentSamplesAccumulateUntilTheyCanMeasureSpeed() throws {
        var rate = DownloadRate()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        rate.add(bytes: 0, at: start)
        for sample in 1...10 {
            rate.add(bytes: Int64(sample * 10), at: start.addingTimeInterval(Double(sample) / 100))
        }
        #expect(abs(try #require(rate.bytesPerSecond) - 1_000) < 0.001)
        #expect(abs(try #require(rate.secondsLeft(completed: 100, total: 1_100)) - 1) < 0.001)
    }

    @Test func ignoresOutOfOrderSamples() {
        var rate = DownloadRate()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        rate.add(bytes: 0, at: start)
        rate.add(bytes: 1_000, at: start.addingTimeInterval(1))
        rate.add(bytes: 500, at: start.addingTimeInterval(0.5))
        rate.add(bytes: 2_000, at: start.addingTimeInterval(2))
        #expect(rate.bytesPerSecond == 1_000)
    }

    @Test func negativeByteCountsDoNotOverflowSpeedOrETA() throws {
        var rate = DownloadRate()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        rate.add(bytes: Int64.min, at: start)
        rate.add(bytes: 1_000, at: start.addingTimeInterval(1))
        #expect(rate.bytesPerSecond == 1_000)
        #expect(try #require(rate.secondsLeft(completed: Int64.min, total: Int64.max)).isFinite)
        #expect(rate.secondsLeft(completed: 2_000, total: 1_000) == 0)
    }
}
