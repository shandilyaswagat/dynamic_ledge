import Foundation

/// Local token counts, never prompts or responses. Cached input is included in input.
struct AIDailyTokens: Codable, Equatable, Identifiable, Sendable {
    var id: Date { day }
    let day: Date
    var input: Int = 0
    var output: Int = 0
    var cached: Int = 0
    var total: Int { input + output }
}

struct AITokenHistory: Codable, Equatable, Sendable {
    var days: [AIDailyTokens] = []
    var isPartial = false
    var checkedAt: Date?
}

/// User-supplied blended USD rates. These estimates are not subscription bills.
struct AICostRates: Codable, Equatable, Sendable {
    var input = ""
    var output = ""
    var cached = ""

    func estimate(_ tokens: AIDailyTokens) -> Double? {
        func rate(_ value: String) -> Double? {
            guard let number = Double(value), number.isFinite, number >= 0 else { return nil }
            return number
        }
        guard let inputRate = rate(input), let outputRate = rate(output),
              tokens.input >= tokens.cached, tokens.cached >= 0, tokens.output >= 0 else { return nil }
        let cacheRate = rate(cached)
        guard tokens.cached == 0 || cacheRate != nil else { return nil }
        let value = (Double(tokens.input - tokens.cached) * inputRate
            + Double(tokens.output) * outputRate + Double(tokens.cached) * (cacheRate ?? 0)) / 1_000_000
        return value.isFinite ? value : nil
    }
}

/// Samples of allowance remaining, not amounts to sum into token consumption.
struct AIQuotaSample: Codable, Identifiable, Sendable {
    var id: String { "\(provider.rawValue)-\(date.timeIntervalSince1970)" }
    let provider: AIProvider
    let date: Date
    let remaining: Double
}

enum AIUsageHistory {
    static func recording(_ usages: [AIProviderUsage], into samples: [AIQuotaSample], now: Date) -> [AIQuotaSample] {
        let cutoff = now.addingTimeInterval(-7 * 86400)
        var result = samples.filter { $0.date >= cutoff && $0.date <= now && $0.remaining.isFinite }
        for usage in usages where usage.status.isSuccess && !usage.isStale(relativeTo: now) {
            guard let date = usage.lastUpdated,
                  let remaining = usage.windows.compactMap(\.remainingPercent).min(),
                  !result.contains(where: { $0.provider == usage.provider && $0.date == date }) else { continue }
            result.append(AIQuotaSample(provider: usage.provider, date: date, remaining: remaining))
        }
        return Array(result.sorted { $0.date < $1.date }.suffix(4096))
    }
}
