import Foundation
import Testing
@testable import NotchKit

@Suite("Antigravity quota pools")
struct AntigravityQuotaTests {
    @Test func keepsPoolsAndResetTimesSeparate() throws {
        let data = Data(#"{"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"window":"weekly","remainingFraction":0.87,"resetTime":"2026-11-07T15:50:18Z"},{"window":"5h","remainingFraction":1}]},{"displayName":"Claude and GPT models","buckets":[{"window":"weekly","remainingFraction":0.5}]}]}}"#.utf8)
        let usage = try #require(AntigravityQuotaReader.parse(data))
        #expect(usage.windows.count == 3)
        #expect(usage.windows[0].remainingPercent == 87)
        #expect(usage.windows[0].resetsAt != nil)
        #expect(usage.windows[1].remainingPercent == 100)
        #expect(usage.windows[2].remainingPercent == 50)
        #expect(Set(usage.windows.map(\.id)).count == 3)
        #expect(usage.tokens == nil)
    }
    @Test func rejectsMissingAndInvalidQuota() {
        for raw in ["{}", #"{"response":{"groups":[]}}"#,
                    #"{"response":{"groups":[{"displayName":"Gemini","buckets":[{"window":"weekly","remainingFraction":true},{"window":"5h","remainingFraction":2}]}]}}"#] {
            #expect(AntigravityQuotaReader.parse(Data(raw.utf8)) == nil)
        }
    }
}
