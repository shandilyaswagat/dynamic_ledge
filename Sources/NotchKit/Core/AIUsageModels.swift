import Foundation
import SwiftUI

/// Assistants whose usage limits can be read on this Mac. Claude Code isn't one: it keeps its
/// limits only on Anthropic's servers, reachable only with its sign-in token, which the app
/// never touches.
public enum AIProvider: String, CaseIterable, Sendable, Codable, Identifiable {
    case codex = "codex"
    case antigravity = "antigravity"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex: "OpenAI Codex"
        case .antigravity: "Antigravity"
        }
    }

    public var shortName: String {
        switch self {
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        }
    }

    public var symbolName: String {
        switch self {
        case .codex: "cpu.fill"
        case .antigravity: "chevron.left.forwardslash.chevron.right"
        }
    }

    public var brandColor: Color {
        switch self {
        case .codex: Color(red: 0.15, green: 0.68, blue: 0.50)
        case .antigravity: Color(red: 0.26, green: 0.52, blue: 0.96)
        }
    }

    public var documentationURL: URL {
        switch self {
        case .codex:
            URL(string: "https://platform.openai.com/docs/guides/rate-limits")!
        case .antigravity:
            URL(string: "https://antigravity.google/docs")!
        }
    }

    /// Explains how data is fetched and privacy guarantees.
    public var integrationNotice: String {
        switch self {
        case .codex:
            "Asks the signed-in Codex app on this Mac for its plan limits."
        case .antigravity:
            "Asks the running Antigravity app on this Mac for its limits, and reads its session logs in ~/.gemini."
        }
    }
}

/// A specific rate-limit or quota window (e.g. 5-hour rolling session, weekly quota, daily request limit).
public struct AIUsageWindow: Sendable, Codable, Equatable, Identifiable {
    public var id: String { name }

    /// Name of the quota window (e.g. "Session Quota", "Weekly Quota", "Requests / Minute").
    public let name: String

    /// Percentage of the window consumed (0.0 to 100.0), if provided by the source.
    public let usedPercent: Double?

    /// Remaining percentage (0.0 to 100.0).
    public var remainingPercent: Double? {
        usedPercent.map { max(0, min(100, 100.0 - $0)) }
    }

    /// Observed or reported count within the window.
    public let usedCount: Int?

    /// Maximum count limit for the window, if available.
    public let limitCount: Int?

    /// Exact reset timestamp, if provided by the source.
    public let resetsAt: Date?

    /// Whether this window is an estimate or an official server report.
    public let isEstimated: Bool

    /// Description of the source (e.g. "Anthropic Rate Limit Header", "OpenAI Usage API").
    public let sourceDescription: String

    public init(
        name: String,
        usedPercent: Double? = nil,
        usedCount: Int? = nil,
        limitCount: Int? = nil,
        resetsAt: Date? = nil,
        isEstimated: Bool = false,
        sourceDescription: String
    ) {
        self.name = name
        self.usedPercent = usedPercent.map { max(0, min(100, $0)) }
        self.usedCount = usedCount
        self.limitCount = limitCount
        self.resetsAt = resetsAt
        self.isEstimated = isEstimated
        self.sourceDescription = sourceDescription
    }

    /// Formats a human-readable countdown to reset time in the user's local timezone.
    public func countdownString(from now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        if remaining <= 0 {
            return "Resetting soon"
        }
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 24 {
            let days = hours / 24
            let remainingHours = hours % 24
            return "resets in \(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "resets in \(hours)h \(minutes)m"
        } else if minutes > 0 {
            let seconds = Int(remaining) % 60
            return "resets in \(minutes)m \(seconds)s"
        } else {
            let seconds = max(1, Int(remaining))
            return "resets in \(seconds)s"
        }
    }

    /// Formats the reset time in the local timezone (e.g. "Today at 3:15 PM").
    public func localResetTimeString() -> String? {
        guard let resetsAt else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = Calendar.current.isDateInToday(resetsAt) ? .none : .short
        return formatter.string(from: resetsAt)
    }
}

/// Token usage broken down by type when exposed by the provider.
public struct AITokenBreakdown: Sendable, Codable, Equatable {
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let cacheReadTokens: Int?
    public let cacheWriteTokens: Int?
    public let totalTokens: Int?

    public init(
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        cacheReadTokens: Int? = nil,
        cacheWriteTokens: Int? = nil,
        totalTokens: Int? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        if let totalTokens {
            self.totalTokens = totalTokens
        } else if promptTokens != nil || completionTokens != nil {
            self.totalTokens = (promptTokens ?? 0) + (completionTokens ?? 0)
        } else {
            self.totalTokens = nil
        }
    }

    public static func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }
}

/// Status of an AI provider's connection and data availability.
public enum AIProviderStatus: Sendable, Codable, Equatable {
    case unconfigured(String)
    case loading
    case active
    case signedOut(String)
    case offline(String)
    case error(String)
    case unavailable(String)

    public var isSuccess: Bool {
        if case .active = self { return true }
        return false
    }

    public var statusDescription: String {
        switch self {
        case .unconfigured(let msg): msg
        case .loading: "Checking usage…"
        case .active: "Connected"
        case .signedOut(let msg): msg
        case .offline(let msg): msg
        case .error(let msg): msg
        case .unavailable(let msg): msg
        }
    }
}

/// Consolidated usage and quota information for a single AI provider.
public struct AIProviderUsage: Sendable, Codable, Equatable, Identifiable {
    public var id: String { provider.rawValue }

    public let provider: AIProvider
    public let status: AIProviderStatus
    public let accountName: String?
    public let plan: String?
    public let model: String?
    public let windows: [AIUsageWindow]
    public let tokens: AITokenBreakdown?
    public let costEstimate: String?
    public let lastUpdated: Date?
    public let attribution: String

    public init(
        provider: AIProvider,
        status: AIProviderStatus,
        accountName: String? = nil,
        plan: String? = nil,
        model: String? = nil,
        windows: [AIUsageWindow] = [],
        tokens: AITokenBreakdown? = nil,
        costEstimate: String? = nil,
        lastUpdated: Date? = nil,
        attribution: String
    ) {
        self.provider = provider
        self.status = status
        self.accountName = accountName
        self.plan = plan
        self.model = model
        self.windows = windows
        self.tokens = tokens
        self.costEstimate = costEstimate
        self.lastUpdated = lastUpdated
        self.attribution = attribution
    }

    /// Whether data is considered stale (older than 15 minutes).
    public func isStale(relativeTo now: Date = Date()) -> Bool {
        guard let lastUpdated else { return true }
        return now.timeIntervalSince(lastUpdated) > 15 * 60
    }

    /// The primary quota window to display in compact / widget representations.
    public var primaryWindow: AIUsageWindow? {
        windows.first
    }

    /// A placeholder unconfigured state.
    public static func unconfigured(for provider: AIProvider, message: String = "Not connected yet.") -> AIProviderUsage {
        AIProviderUsage(
            provider: provider,
            status: .unconfigured(message),
            attribution: provider.integrationNotice
        )
    }
}

/// Provider cards are shown only when selected and connected.
enum AIUsageSelection {
    static func visible(_ usages: [AIProvider: AIProviderUsage], selected: Set<AIProvider>) -> [AIProviderUsage] {
        AIProvider.allCases.compactMap { provider in
            guard selected.contains(provider), let usage = usages[provider], usage.status.isSuccess else { return nil }
            return usage
        }
    }
}
