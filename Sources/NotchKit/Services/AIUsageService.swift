import Foundation
import Observation
import os

/// Reads coding assistants' usage from what they keep on this Mac. Nothing is sent anywhere, and
/// no API keys are asked for or stored.
@MainActor
@Observable
public final class AIUsageService {
    public private(set) var usages: [AIProvider: AIProviderUsage] = [:]
    public private(set) var isRefreshing: Bool = false
    public private(set) var lastRefreshAttempt: Date?
    public private(set) var lastError: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let log = Logger(subsystem: Log.subsystem, category: "aiUsage")

    /// Minimum time between background refreshes (e.g. 5 minutes).
    public static let minimumRefreshInterval: TimeInterval = 300
    /// Minimum time between manual refreshes to prevent abuse (e.g. 5 seconds).
    public static let minimumManualInterval: TimeInterval = 5

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadCachedUsages()
    }

    /// Primary aggregated status for compact widget display.
    public var hasData: Bool {
        usages.values.contains { $0.status.isSuccess }
    }

    func visibleUsages(selected: Set<AIProvider>) -> [AIProviderUsage] {
        AIUsageSelection.visible(usages, selected: selected)
    }

    /// Returns the most constrained remaining quota percentage across all active providers.
    public var minimumRemainingPercent: Double? {
        let activeWindows = usages.values.filter { $0.status.isSuccess }.flatMap(\.windows)
        let percentages = activeWindows.compactMap(\.remainingPercent)
        return percentages.min()
    }

    /// Returns the nearest upcoming reset date among all active providers.
    public var earliestResetDate: Date? {
        let activeWindows = usages.values.filter { $0.status.isSuccess }.flatMap(\.windows)
        let dates = activeWindows.compactMap(\.resetsAt).filter { $0 > Date() }
        return dates.min()
    }

    // MARK: - Refresh Lifecycle

    public func startAutomaticRefreshes(interval: TimeInterval = 300) {
        guard timer == nil else { return }
        refreshAll(userInitiated: false)
        timer = Timer.scheduledTimer(withTimeInterval: max(60, interval), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAll(userInitiated: false)
            }
        }
    }

    public func stopAutomaticRefreshes() {
        timer?.invalidate()
        timer = nil
    }

    public func refreshAll(userInitiated: Bool = false) {
        guard !isRefreshing else { return }
        if userInitiated, let last = lastRefreshAttempt, Date().timeIntervalSince(last) < Self.minimumManualInterval {
            log.info("Skipping manual refresh: cooldown active.")
            return
        }

        lastRefreshAttempt = Date()
        isRefreshing = true
        lastError = nil

        Task {
            let claudeEnabled = defaults.object(forKey: "aiUsage.claudeEnabled") as? Bool ?? true
            let codexEnabled = defaults.object(forKey: "aiUsage.codexEnabled") as? Bool ?? true
            let antigravityEnabled = defaults.object(forKey: "aiUsage.antigravityEnabled") as? Bool ?? true
            let claudeUsage = claudeEnabled ? await fetchClaudeCodeUsage() : AIProviderUsage.unconfigured(for: .claudeCode, message: "Claude tracking is off.")
            let codexUsage = codexEnabled ? await fetchCodexUsage() : AIProviderUsage.unconfigured(for: .codex, message: "Codex tracking is off.")
            let antigravityUsage = antigravityEnabled ? await fetchAntigravityUsage() : AIProviderUsage.unconfigured(for: .antigravity, message: "Antigravity tracking is off.")

            self.usages[.claudeCode] = claudeUsage
            self.usages[.codex] = codexUsage
            self.usages[.antigravity] = antigravityUsage
            self.isRefreshing = false
            self.saveCachedUsages()
        }
    }

    // MARK: - Claude Code Provider

    public func fetchClaudeCodeUsage() async -> AIProviderUsage {
        parseLocalClaudeSession() ?? AIProviderUsage(
            provider: .claudeCode,
            status: .unconfigured("Claude Code isn't set up on this Mac."),
            attribution: AIProvider.claudeCode.integrationNotice
        )
    }

    /// Inspects local Claude Code CLI configuration file (`~/.claude.json`) if present.
    private func parseLocalClaudeSession() -> AIProviderUsage? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeConfigFile = home.appendingPathComponent(".claude.json")
        guard FileManager.default.fileExists(atPath: claudeConfigFile.path),
              let data = try? Data(contentsOf: claudeConfigFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let oauthAccount = json["oauthAccount"] as? [String: Any]
        let email = oauthAccount?["emailAddress"] as? String ?? json["email"] as? String
        let plan = json["plan"] as? String ?? "Claude Pro / Team"

        // Local observed session usage stats
        var windows: [AIUsageWindow] = []
        if let stats = json["sessionStats"] as? [String: Any] {
            if let usedPercent = stats["usedPercent"] as? Double {
                let resetTimestamp = stats["resetsAt"] as? TimeInterval
                let resetsAt = resetTimestamp.map { Date(timeIntervalSince1970: $0) }
                windows.append(AIUsageWindow(
                    name: "5-Hour Session Limit",
                    usedPercent: usedPercent,
                    resetsAt: resetsAt,
                    isEstimated: true,
                    sourceDescription: "Local Claude Code Session (~/.claude.json)"
                ))
            }
        }

        guard !windows.isEmpty else {
            return AIProviderUsage(provider: .claudeCode, status: .unavailable("Claude Code's local configuration does not provide subscription limits."), attribution: "Claude Code local configuration")
        }
        return AIProviderUsage(
            provider: .claudeCode,
            status: .active,
            accountName: email,
            plan: plan,
            windows: windows,
            lastUpdated: Date(),
            attribution: "Local Claude Code Session (~/.claude.json)"
        )
    }

    // MARK: - OpenAI Codex Provider

    public func fetchCodexUsage() async -> AIProviderUsage {
        await CodexUsageReader.read()
    }

    // MARK: - Google Antigravity Provider

    public func fetchAntigravityUsage() async -> AIProviderUsage {
        await AntigravityUsageReader.read()
    }

    // MARK: - Persistence / Cache

    private func saveCachedUsages() {
        if let encoded = try? JSONEncoder().encode(usages) {
            defaults.set(encoded, forKey: "aiUsageCachedState")
        }
    }

    private func loadCachedUsages() {
        guard let data = defaults.data(forKey: "aiUsageCachedState"),
              let decoded = try? JSONDecoder().decode([AIProvider: AIProviderUsage].self, from: data) else {
            usages[.claudeCode] = .unconfigured(for: .claudeCode)
            usages[.codex] = .unconfigured(for: .codex)
            usages[.antigravity] = .unconfigured(for: .antigravity)
            return
        }
        self.usages = decoded
    }
}
