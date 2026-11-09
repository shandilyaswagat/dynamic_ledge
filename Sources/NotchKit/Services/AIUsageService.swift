import Foundation
import Observation
import os

/// Reads coding assistants' usage through what they run on this Mac. This app sends nothing
/// itself (Codex checks with OpenAI using its own sign-in), and no API keys are asked for or stored.
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
            let codexEnabled = defaults.object(forKey: "aiUsage.codexEnabled") as? Bool ?? true
            let antigravityEnabled = defaults.object(forKey: "aiUsage.antigravityEnabled") as? Bool ?? true
            // Both at once: Codex can take a few seconds to answer.
            async let codex = codexEnabled ? fetchCodexUsage() : AIProviderUsage.unconfigured(for: .codex, message: "Codex tracking is off.")
            async let antigravity = antigravityEnabled ? fetchAntigravityUsage() : AIProviderUsage.unconfigured(for: .antigravity, message: "Antigravity tracking is off.")
            let (codexUsage, antigravityUsage) = await (codex, antigravity)

            self.usages[.codex] = codexUsage
            self.usages[.antigravity] = antigravityUsage
            self.isRefreshing = false
            self.saveCachedUsages()
        }
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
              // Saved by earlier builds with Claude Code in it, this fails and starts fresh.
              let decoded = try? JSONDecoder().decode([AIProvider: AIProviderUsage].self, from: data) else {
            usages[.codex] = .unconfigured(for: .codex)
            usages[.antigravity] = .unconfigured(for: .antigravity)
            return
        }
        self.usages = decoded
    }
}
