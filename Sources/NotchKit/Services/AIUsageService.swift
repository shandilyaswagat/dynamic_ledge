import Foundation
import Observation
import os

/// Protocol to abstract network fetching for AI usage, allowing deterministic unit testing.
public protocol AIUsageNetworking: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// Default implementation using URLSession.
public struct DefaultAIUsageNetworking: AIUsageNetworking {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

/// Service that coordinates fetching, rate-limiting, and managing AI agent usage metrics.
@MainActor
@Observable
public final class AIUsageService {
    public private(set) var usages: [AIProvider: AIProviderUsage] = [:]
    public private(set) var isRefreshing: Bool = false
    public private(set) var lastRefreshAttempt: Date?
    public private(set) var lastError: String?

    @ObservationIgnored private let networking: AIUsageNetworking
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let log = Logger(subsystem: Log.subsystem, category: "aiUsage")

    /// Minimum time between background refreshes (e.g. 5 minutes).
    public static let minimumRefreshInterval: TimeInterval = 300
    /// Minimum time between manual refreshes to prevent abuse (e.g. 5 seconds).
    public static let minimumManualInterval: TimeInterval = 5

    public init(
        networking: AIUsageNetworking = DefaultAIUsageNetworking(),
        defaults: UserDefaults = .standard
    ) {
        self.networking = networking
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
        let apiKey = defaults.string(forKey: "aiUsageClaudeApiKey")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let useLocalCLI = defaults.object(forKey: "aiUsageClaudeUseLocalCLI") as? Bool ?? true

        // 1. Check if user configured an API key
        if !apiKey.isEmpty {
            return await fetchClaudeFromAPI(apiKey: apiKey)
        }

        // 2. Check local Claude Code CLI session if opted-in
        if useLocalCLI {
            if let localUsage = parseLocalClaudeSession() {
                return localUsage
            }
        }

        return AIProviderUsage(
            provider: .claudeCode,
            status: .unconfigured("Add an Anthropic API Key or enable local Claude Code CLI in Settings."),
            attribution: AIProvider.claudeCode.integrationNotice
        )
    }

    private func fetchClaudeFromAPI(apiKey: String) async -> AIProviderUsage {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        // Minimal probe to obtain rate-limit headers without consuming tokens if unauthorized
        request.httpBody = Data("{\"model\":\"claude-3-haiku-20240307\",\"max_tokens\":1,\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}".utf8)

        do {
            let (data, response) = try await networking.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return AIProviderUsage(
                    provider: .claudeCode,
                    status: .error("Invalid server response"),
                    attribution: "Anthropic API"
                )
            }

            if http.statusCode == 401 {
                return AIProviderUsage(
                    provider: .claudeCode,
                    status: .signedOut("Invalid API Key. Please update in Settings."),
                    attribution: "Anthropic API"
                )
            }

            if http.statusCode == 429 {
                let windows = Self.parseAnthropicRateLimitHeaders(http.allHeaderFields)
                return AIProviderUsage(
                    provider: .claudeCode,
                    status: .active,
                    plan: "Anthropic API",
                    windows: windows,
                    lastUpdated: Date(),
                    attribution: "Anthropic Rate Limit Headers (429 Rate Limit)"
                )
            }

            guard (200..<300).contains(http.statusCode) else {
                return AIProviderUsage(provider: .claudeCode, status: .error("Anthropic request failed (HTTP \(http.statusCode))."), attribution: "Anthropic API")
            }
            let windows = Self.parseAnthropicRateLimitHeaders(http.allHeaderFields)
            let tokens = Self.parseAnthropicMessageTokens(data)

            return AIProviderUsage(
                provider: .claudeCode,
                status: .active,
                plan: "Anthropic API",
                windows: windows,
                tokens: tokens,
                lastUpdated: Date(),
                attribution: "Anthropic API & Official Rate Limit Headers"
            )
        } catch {
            return AIProviderUsage(
                provider: .claudeCode,
                status: .offline("Network unavailable: \(error.localizedDescription)"),
                attribution: "Anthropic API"
            )
        }
    }

    nonisolated public static func parseAnthropicRateLimitHeaders(_ headers: [AnyHashable: Any]) -> [AIUsageWindow] {
        var windows: [AIUsageWindow] = []

        // Requests limit
        if let limitStr = headers["anthropic-ratelimit-requests-limit"] as? String,
           let limit = Int(limitStr),
           let remainingStr = headers["anthropic-ratelimit-requests-remaining"] as? String,
           let remaining = Int(remainingStr) {
            let used = max(0, limit - remaining)
            let percent = limit > 0 ? (Double(used) / Double(limit)) * 100.0 : 0.0
            var resetsAt: Date?
            if let resetStr = headers["anthropic-ratelimit-requests-reset"] as? String {
                resetsAt = ISO8601DateFormatter().date(from: resetStr)
            }
            windows.append(AIUsageWindow(
                name: "Requests Window",
                usedPercent: percent,
                usedCount: used,
                limitCount: limit,
                resetsAt: resetsAt,
                isEstimated: false,
                sourceDescription: "Anthropic Requests Rate Limit"
            ))
        }

        // Tokens limit
        if let limitStr = headers["anthropic-ratelimit-tokens-limit"] as? String,
           let limit = Int(limitStr),
           let remainingStr = headers["anthropic-ratelimit-tokens-remaining"] as? String,
           let remaining = Int(remainingStr) {
            let used = max(0, limit - remaining)
            let percent = limit > 0 ? (Double(used) / Double(limit)) * 100.0 : 0.0
            var resetsAt: Date?
            if let resetStr = headers["anthropic-ratelimit-tokens-reset"] as? String {
                resetsAt = ISO8601DateFormatter().date(from: resetStr)
            }
            windows.append(AIUsageWindow(
                name: "Tokens Window",
                usedPercent: percent,
                usedCount: used,
                limitCount: limit,
                resetsAt: resetsAt,
                isEstimated: false,
                sourceDescription: "Anthropic Tokens Rate Limit"
            ))
        }

        // Unified 5-hour session / weekly limit headers if present
        if let sessionPercentStr = headers["anthropic-ratelimit-unified-session-used"] as? String,
           let sessionPercent = Double(sessionPercentStr) {
            var resetsAt: Date?
            if let resetStr = headers["anthropic-ratelimit-unified-session-reset"] as? String {
                resetsAt = ISO8601DateFormatter().date(from: resetStr)
            }
            windows.append(AIUsageWindow(
                name: "5-Hour Session Quota",
                usedPercent: sessionPercent,
                resetsAt: resetsAt,
                isEstimated: false,
                sourceDescription: "Anthropic Unified Quota"
            ))
        }

        return windows
    }

    nonisolated public static func parseAnthropicMessageTokens(_ data: Data) -> AITokenBreakdown? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = json["usage"] as? [String: Any] else {
            return nil
        }
        let input = usage["input_tokens"] as? Int
        let output = usage["output_tokens"] as? Int
        let cacheRead = usage["cache_read_input_tokens"] as? Int
        let cacheWrite = usage["cache_creation_input_tokens"] as? Int
        return AITokenBreakdown(
            promptTokens: input,
            completionTokens: output,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite
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
        let useLocalCLI = defaults.object(forKey: "aiUsage.codexUseLocalCLI") as? Bool ?? true
        if useLocalCLI {
            let local = await CodexUsageReader.read()
            if local.status.isSuccess {
                return local
            }
            let apiKey = defaults.string(forKey: "aiUsageCodexApiKey")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if apiKey.isEmpty {
                return local
            }
        }
        let apiKey = defaults.string(forKey: "aiUsageCodexApiKey")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let orgId = defaults.string(forKey: "aiUsageCodexOrgId")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !apiKey.isEmpty else {
            return AIProviderUsage(
                provider: .codex,
                status: .unconfigured("Enable signed-in Codex CLI in Settings to see subscription limits, or add an API key for separate API usage."),
                attribution: AIProvider.codex.integrationNotice
            )
        }

        return await fetchCodexFromAPI(apiKey: apiKey, orgId: orgId)
    }

    private func fetchCodexFromAPI(apiKey: String, orgId: String) async -> AIProviderUsage {
        // Query official OpenAI usage completions endpoint for current day
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startTime = Int(today.timeIntervalSince1970)

        var components = URLComponents(string: "https://api.openai.com/v1/organization/usage/completions")!
        components.queryItems = [
            URLQueryItem(name: "start_time", value: "\(startTime)"),
            URLQueryItem(name: "bucket_width", value: "1d")
        ]

        guard let url = components.url else {
            return AIProviderUsage(
                provider: .codex,
                status: .error("Invalid URL"),
                attribution: "OpenAI Usage API"
            )
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if !orgId.isEmpty {
            request.setValue(orgId, forHTTPHeaderField: "OpenAI-Organization")
        }

        do {
            let (data, response) = try await networking.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return AIProviderUsage(
                    provider: .codex,
                    status: .error("Invalid server response"),
                    attribution: "OpenAI Usage API"
                )
            }

            if http.statusCode == 401 {
                return AIProviderUsage(
                    provider: .codex,
                    status: .signedOut("Invalid API Key. Please verify in Settings."),
                    attribution: "OpenAI Platform API"
                )
            }

            if http.statusCode == 403 {
                // Not an admin API key; fall back gracefully to rate-limit header probe
                return await probeOpenAIRateLimits(apiKey: apiKey, orgId: orgId)
            }

            guard (200..<300).contains(http.statusCode) else {
                return AIProviderUsage(provider: .codex, status: .error("OpenAI usage request failed (HTTP \(http.statusCode))."), attribution: "OpenAI Usage API")
            }
            let (tokens, cost) = Self.parseOpenAIUsageResponse(data)
            let windows = Self.parseOpenAIRateLimitHeaders(http.allHeaderFields)

            return AIProviderUsage(
                provider: .codex,
                status: .active,
                plan: "OpenAI Platform",
                windows: windows,
                tokens: tokens,
                costEstimate: cost,
                lastUpdated: Date(),
                attribution: "Official OpenAI Usage API"
            )
        } catch {
            return AIProviderUsage(
                provider: .codex,
                status: .offline("Network unavailable: \(error.localizedDescription)"),
                attribution: "OpenAI Usage API"
            )
        }
    }

    private func probeOpenAIRateLimits(apiKey: String, orgId: String) async -> AIProviderUsage {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if !orgId.isEmpty {
            request.setValue(orgId, forHTTPHeaderField: "OpenAI-Organization")
        }

        do {
            let (_, response) = try await networking.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return AIProviderUsage(
                    provider: .codex,
                    status: .error("Probe failed"),
                    attribution: "OpenAI Rate Limits"
                )
            }

            if http.statusCode == 401 {
                return AIProviderUsage(
                    provider: .codex,
                    status: .signedOut("Unauthorized API Key"),
                    attribution: "OpenAI API"
                )
            }

            let windows = Self.parseOpenAIRateLimitHeaders(http.allHeaderFields)
            return AIProviderUsage(
                provider: .codex,
                status: .active,
                plan: "OpenAI API",
                windows: windows,
                lastUpdated: Date(),
                attribution: "OpenAI Rate Limit Headers"
            )
        } catch {
            return AIProviderUsage(
                provider: .codex,
                status: .offline("Network offline"),
                attribution: "OpenAI API"
            )
        }
    }

    nonisolated public static func parseOpenAIRateLimitHeaders(_ headers: [AnyHashable: Any]) -> [AIUsageWindow] {
        var windows: [AIUsageWindow] = []

        // Requests limit
        if let limitStr = headers["x-ratelimit-limit-requests"] as? String,
           let limit = Int(limitStr),
           let remainingStr = headers["x-ratelimit-remaining-requests"] as? String,
           let remaining = Int(remainingStr) {
            let used = max(0, limit - remaining)
            let percent = limit > 0 ? (Double(used) / Double(limit)) * 100.0 : 0.0
            var resetsAt: Date?
            if let resetStr = headers["x-ratelimit-reset-requests"] as? String {
                resetsAt = parseOpenAIResetHeader(resetStr)
            }
            windows.append(AIUsageWindow(
                name: "Requests Limit",
                usedPercent: percent,
                usedCount: used,
                limitCount: limit,
                resetsAt: resetsAt,
                isEstimated: false,
                sourceDescription: "OpenAI Rate Limit Headers"
            ))
        }

        // Tokens limit
        if let limitStr = headers["x-ratelimit-limit-tokens"] as? String,
           let limit = Int(limitStr),
           let remainingStr = headers["x-ratelimit-remaining-tokens"] as? String,
           let remaining = Int(remainingStr) {
            let used = max(0, limit - remaining)
            let percent = limit > 0 ? (Double(used) / Double(limit)) * 100.0 : 0.0
            var resetsAt: Date?
            if let resetStr = headers["x-ratelimit-reset-tokens"] as? String {
                resetsAt = parseOpenAIResetHeader(resetStr)
            }
            windows.append(AIUsageWindow(
                name: "Tokens Limit",
                usedPercent: percent,
                usedCount: used,
                limitCount: limit,
                resetsAt: resetsAt,
                isEstimated: false,
                sourceDescription: "OpenAI Rate Limit Headers"
            ))
        }

        return windows
    }

    /// Parses OpenAI reset strings like "6ms", "15s", "2m30s".
    nonisolated public static func parseOpenAIResetHeader(_ string: String, from now: Date = Date()) -> Date? {
        var totalSeconds: Double = 0
        let scanner = Scanner(string: string)
        while !scanner.isAtEnd {
            guard let value = scanner.scanDouble() else { break }
            if scanner.scanString("ms") != nil {
                totalSeconds += value / 1000.0
            } else if scanner.scanString("s") != nil {
                totalSeconds += value
            } else if scanner.scanString("m") != nil {
                totalSeconds += value * 60.0
            } else if scanner.scanString("h") != nil {
                totalSeconds += value * 3600.0
            } else if scanner.scanString("d") != nil {
                totalSeconds += value * 86400.0
            }
        }
        guard totalSeconds > 0 else { return nil }
        return now.addingTimeInterval(totalSeconds)
    }

    nonisolated public static func parseOpenAIUsageResponse(_ data: Data) -> (AITokenBreakdown?, String?) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataArray = json["data"] as? [[String: Any]] else {
            return (nil, nil)
        }

        var totalInput = 0
        var totalOutput = 0
        var totalCost: Double = 0
        var hasCost = false

        for bucket in dataArray {
            if let results = bucket["results"] as? [[String: Any]] {
                for item in results {
                    totalInput += item["input_tokens"] as? Int ?? 0
                    totalOutput += item["output_tokens"] as? Int ?? 0
                }
            } else {
                if let input = bucket["n_context_tokens_total"] as? Int {
                    totalInput += input
                }
                if let output = bucket["n_generated_tokens_total"] as? Int {
                    totalOutput += output
                }
            }
            if let cost = bucket["cost"] as? Double {
                totalCost += cost
                hasCost = true
            }
        }

        let breakdown = (totalInput > 0 || totalOutput > 0)
            ? AITokenBreakdown(promptTokens: totalInput, completionTokens: totalOutput)
            : nil

        let costString = hasCost ? String(format: "$%.2f", totalCost) : nil
        return (breakdown, costString)
    }

    // MARK: - Google Antigravity Provider

    public func fetchAntigravityUsage() async -> AIProviderUsage {
        let useLocal = defaults.object(forKey: "aiUsage.antigravityUseLocal") as? Bool ?? true
        if useLocal {
            let local = await AntigravityUsageReader.read()
            if local.status.isSuccess {
                return local
            }
        }
        let apiKey = defaults.string(forKey: "aiUsageAntigravityApiKey")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !apiKey.isEmpty {
            return AIProviderUsage(
                provider: .antigravity,
                status: .active,
                plan: "Gemini Developer API",
                windows: [
                    AIUsageWindow(name: "Rate Limits", usedPercent: 0, sourceDescription: "Google Gemini API")
                ],
                lastUpdated: Date(),
                attribution: "Google Gemini API Key"
            )
        }
        if !useLocal {
            return AIProviderUsage(
                provider: .antigravity,
                status: .unconfigured("Add a Gemini API Key or enable local Antigravity session in Settings."),
                attribution: AIProvider.antigravity.integrationNotice
            )
        }
        return await AntigravityUsageReader.read()
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
