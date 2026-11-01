import Foundation
import Testing
@testable import NotchKit

private final class MockNetworking: AIUsageNetworking, @unchecked Sendable {
    var handler: ((URLRequest) throws -> (Data, URLResponse))?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let handler {
            return try handler(request)
        }
        throw URLError(.notConnectedToInternet)
    }
}

@MainActor
@Suite("AI Agent Usage - Parsing & Windows")
struct AIUsageParsingTests {
    @Test func anthropicHeaderParsingExtractsWindowsCorrectly() {
        let headers: [AnyHashable: Any] = [
            "anthropic-ratelimit-requests-limit": "1000",
            "anthropic-ratelimit-requests-remaining": "800",
            "anthropic-ratelimit-requests-reset": "2026-11-01T12:00:00Z",
            "anthropic-ratelimit-tokens-limit": "40000",
            "anthropic-ratelimit-tokens-remaining": "10000",
            "anthropic-ratelimit-tokens-reset": "2026-11-01T13:00:00Z",
            "anthropic-ratelimit-unified-session-used": "42.5",
            "anthropic-ratelimit-unified-session-reset": "2026-11-01T15:30:00Z"
        ]

        let windows = AIUsageService.parseAnthropicRateLimitHeaders(headers)
        #expect(windows.count == 3)

        let reqWindow = windows.first { $0.name == "Requests Window" }
        #expect(reqWindow != nil)
        #expect(reqWindow?.usedCount == 200)
        #expect(reqWindow?.limitCount == 1000)
        #expect(reqWindow?.usedPercent == 20.0)
        #expect(reqWindow?.remainingPercent == 80.0)

        let tokenWindow = windows.first { $0.name == "Tokens Window" }
        #expect(tokenWindow != nil)
        #expect(tokenWindow?.usedCount == 30000)
        #expect(tokenWindow?.limitCount == 40000)
        #expect(tokenWindow?.usedPercent == 75.0)
        #expect(tokenWindow?.remainingPercent == 25.0)

        let sessionWindow = windows.first { $0.name == "5-Hour Session Quota" }
        #expect(sessionWindow != nil)
        #expect(sessionWindow?.usedPercent == 42.5)
        #expect(sessionWindow?.remainingPercent == 57.5)
    }

    @Test func anthropicTokenBreakdownExtractsAllTypes() {
        let jsonString = """
        {
            "id": "msg_01",
            "type": "message",
            "role": "assistant",
            "usage": {
                "input_tokens": 1200,
                "output_tokens": 350,
                "cache_read_input_tokens": 500,
                "cache_creation_input_tokens": 100
            }
        }
        """
        let data = Data(jsonString.utf8)
        let breakdown = AIUsageService.parseAnthropicMessageTokens(data)
        #expect(breakdown != nil)
        #expect(breakdown?.promptTokens == 1200)
        #expect(breakdown?.completionTokens == 350)
        #expect(breakdown?.cacheReadTokens == 500)
        #expect(breakdown?.cacheWriteTokens == 100)
        #expect(breakdown?.totalTokens == 1550)
    }

    @Test func openAIUsageResponseExtractsDailyTokensAndCost() {
        let jsonString = """
        {
            "data": [
                {
                    "n_context_tokens_total": 45000,
                    "n_generated_tokens_total": 5000,
                    "cost": 0.42
                }
            ]
        }
        """
        let data = Data(jsonString.utf8)
        let (tokens, cost) = AIUsageService.parseOpenAIUsageResponse(data)
        #expect(tokens != nil)
        #expect(tokens?.promptTokens == 45000)
        #expect(tokens?.completionTokens == 5000)
        #expect(tokens?.totalTokens == 50000)
        #expect(cost == "$0.42")
    }

    @Test func openAIRateLimitHeadersParsing() {
        let headers: [AnyHashable: Any] = [
            "x-ratelimit-limit-requests": "500",
            "x-ratelimit-remaining-requests": "450",
            "x-ratelimit-reset-requests": "12s",
            "x-ratelimit-limit-tokens": "100000",
            "x-ratelimit-remaining-tokens": "20000",
            "x-ratelimit-reset-tokens": "6m"
        ]
        let windows = AIUsageService.parseOpenAIRateLimitHeaders(headers)
        #expect(windows.count == 2)
        let reqWindow = windows.first { $0.name == "Requests Limit" }
        #expect(reqWindow?.usedCount == 50)
        #expect(reqWindow?.remainingPercent == 90.0)

        let tokWindow = windows.first { $0.name == "Tokens Limit" }
        #expect(tokWindow?.usedCount == 80000)
        #expect(tokWindow?.remainingPercent == 20.0)
    }

    @Test func missingDataDoesNotInventValues() {
        let emptyHeaders: [AnyHashable: Any] = [:]
        let windows = AIUsageService.parseAnthropicRateLimitHeaders(emptyHeaders)
        #expect(windows.isEmpty, "No windows are invented from empty headers")

        let invalidJson = Data("{}".utf8)
        let tokens = AIUsageService.parseAnthropicMessageTokens(invalidJson)
        #expect(tokens == nil, "No tokens are invented from missing usage JSON")

        let window = AIUsageWindow(
            name: "Unknown Quota",
            usedPercent: nil,
            usedCount: nil,
            limitCount: nil,
            resetsAt: nil,
            sourceDescription: "Test"
        )
        #expect(window.remainingPercent == nil)
        #expect(window.countdownString() == nil)
        #expect(window.localResetTimeString() == nil)
    }

    @Test func tokenCountFormatting() {
        #expect(AITokenBreakdown.formatCount(450) == "450")
        #expect(AITokenBreakdown.formatCount(1200) == "1.2K")
        #expect(AITokenBreakdown.formatCount(1_500_000) == "1.5M")
    }
}

@MainActor
@Suite("AI Agent Usage - Reset Times & Countdowns")
struct AIUsageResetTimeTests {
    @Test func countdownFormattingAcrossDurations() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // 30 seconds left
        let t30s = now.addingTimeInterval(30)
        let w30s = AIUsageWindow(name: "Test", resetsAt: t30s, sourceDescription: "Test")
        #expect(w30s.countdownString(from: now) == "resets in 30s")

        // 5 minutes and 12 seconds left
        let t5m = now.addingTimeInterval(312)
        let w5m = AIUsageWindow(name: "Test", resetsAt: t5m, sourceDescription: "Test")
        #expect(w5m.countdownString(from: now) == "resets in 5m 12s")

        // 3 hours and 25 minutes left
        let t3h = now.addingTimeInterval(3 * 3600 + 25 * 60)
        let w3h = AIUsageWindow(name: "Test", resetsAt: t3h, sourceDescription: "Test")
        #expect(w3h.countdownString(from: now) == "resets in 3h 25m")

        // 2 days and 4 hours left
        let t2d = now.addingTimeInterval(2 * 86400 + 4 * 3600)
        let w2d = AIUsageWindow(name: "Test", resetsAt: t2d, sourceDescription: "Test")
        #expect(w2d.countdownString(from: now) == "resets in 2d 4h")

        // Expired or resetting now
        let past = now.addingTimeInterval(-5)
        let wpast = AIUsageWindow(name: "Test", resetsAt: past, sourceDescription: "Test")
        #expect(wpast.countdownString(from: now) == "Resetting soon")
    }
}

@MainActor
@Suite("AI Agent Usage - Service Lifecycle & Network States")
struct AIUsageServiceTests {
    @Test func automaticRefreshChecksImmediatelyAndStartsOnlyOnce() async throws {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "aiUsage.claudeEnabled")
        defaults.set(false, forKey: "aiUsage.codexEnabled")
        defaults.set(false, forKey: "aiUsage.antigravityEnabled")
        let service = AIUsageService(networking: MockNetworking(), defaults: defaults)
        defer { service.stopAutomaticRefreshes() }
        service.startAutomaticRefreshes()
        #expect(service.lastRefreshAttempt != nil)
        let attempt = service.lastRefreshAttempt
        let deadline = Date().addingTimeInterval(3)
        while service.isRefreshing && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!service.isRefreshing)
        service.startAutomaticRefreshes()
        #expect(service.lastRefreshAttempt == attempt)
        #expect(!service.hasData)
    }

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: "AIUsageTests-\(UUID().uuidString)")!
        // Never inherit this Mac's live connections in network unit tests.
        defaults.set(false, forKey: "aiUsage.codexUseLocalCLI")
        defaults.set(false, forKey: "aiUsageClaudeUseLocalCLI")
        defaults.set(false, forKey: "aiUsage.antigravityUseLocal")
        defaults.set("", forKey: "aiUsageCodexApiKey")
        defaults.set("", forKey: "aiUsageClaudeApiKey")
        defaults.set("", forKey: "aiUsageAntigravityApiKey")
        return defaults
    }

    @Test func unconfiguredStateWhenApiKeyMissing() async {
        let defaults = makeDefaults()
        let mock = MockNetworking()
        let service = AIUsageService(networking: mock, defaults: defaults)

        let claude = await service.fetchClaudeCodeUsage()
        if case .unconfigured = claude.status {
            #expect(Bool(true))
        } else {
            Issue.record("Expected unconfigured status for Claude Code without API key")
        }

        let codex = await service.fetchCodexUsage()
        if case .unconfigured = codex.status {
            #expect(Bool(true))
        } else {
            Issue.record("Expected unconfigured status for Codex without API key")
        }

        let antigravity = await service.fetchAntigravityUsage()
        if case .unconfigured = antigravity.status {
            #expect(Bool(true))
        } else {
            Issue.record("Expected unconfigured status for Antigravity without API key or local session")
        }
    }

    @Test func signedOutStateOn401() async {
        let defaults = makeDefaults()
        defaults.set("sk-ant-invalid", forKey: "aiUsageClaudeApiKey")
        let mock = MockNetworking()
        mock.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (Data("{\"error\":{\"message\":\"invalid api key\"}}".utf8), resp)
        }
        let service = AIUsageService(networking: mock, defaults: defaults)
        let usage = await service.fetchClaudeCodeUsage()

        if case .signedOut = usage.status {
            #expect(Bool(true))
        } else {
            Issue.record("Expected signedOut state for HTTP 401")
        }
    }

    @Test func offlineStateOnNetworkFailure() async {
        let defaults = makeDefaults()
        defaults.set("sk-ant-valid", forKey: "aiUsageClaudeApiKey")
        let mock = MockNetworking()
        mock.handler = { _ in
            throw URLError(.cannotConnectToHost)
        }
        let service = AIUsageService(networking: mock, defaults: defaults)
        let usage = await service.fetchClaudeCodeUsage()

        if case .offline = usage.status {
            #expect(Bool(true))
        } else {
            Issue.record("Expected offline state when network throws")
        }
    }

    @Test func manualRefreshCooldownThrottlesRapidRequests() async {
        let defaults = makeDefaults()
        let mock = MockNetworking()
        let service = AIUsageService(networking: mock, defaults: defaults)

        service.refreshAll(userInitiated: true)
        let firstAttempt = service.lastRefreshAttempt
        #expect(firstAttempt != nil)

        // Attempt immediate second manual refresh
        service.refreshAll(userInitiated: true)
        let secondAttempt = service.lastRefreshAttempt
        #expect(firstAttempt == secondAttempt, "Immediate manual refresh must be throttled by cooldown")
    }

    @Test func minimumRemainingPercentAggregatesAcrossProviders() {
        let defaults = makeDefaults()

        let w1 = AIUsageWindow(name: "W1", usedPercent: 40, sourceDescription: "A") // 60% rem
        let w2 = AIUsageWindow(name: "W2", usedPercent: 85, sourceDescription: "B") // 15% rem
        let u1 = AIProviderUsage(provider: .claudeCode, status: .active, windows: [w1], attribution: "A")
        let u2 = AIProviderUsage(provider: .codex, status: .active, windows: [w2], attribution: "B")

        let state: [AIProvider: AIProviderUsage] = [.claudeCode: u1, .codex: u2]
        defaults.set(try? JSONEncoder().encode(state), forKey: "aiUsageCachedState")
        let restored = AIUsageService(networking: MockNetworking(), defaults: defaults)

        #expect(restored.hasData)
        #expect(restored.minimumRemainingPercent == 15.0)
    }
}

@Suite("Codex subscription responses")
struct CodexSubscriptionTests {
    @Test func readsUsageWindowsWithoutInventingTokenCounts() throws {
        let response: [String: Any] = ["result": ["rateLimits": [
            "primary": ["usedPercent": 42, "windowDurationMins": 300, "resetsAt": 1_800_000_000],
            "secondary": ["usedPercent": 80, "windowDurationMins": 10080, "resetsAt": 1_800_010_000],
        ]]]
        let result = CodexUsageReader.parseResponse(response)
        #expect(result.status.isSuccess)
        #expect(result.windows.count == 2)
        try #require(result.windows.count == 2)
        #expect(result.windows[0].name == "5-hour limit")
        #expect(result.windows[0].remainingPercent == 58)
        #expect(result.windows[1].name == "Weekly limit")
        #expect(result.tokens == nil)
    }

    @Test func missingOrInvalidWindowsRemainUnavailable() {
        let empty = CodexUsageReader.parseResponse(["result": ["rateLimits": [:]]])
        #expect(!empty.status.isSuccess)
        let invalid = CodexUsageReader.parseResponse(["result": ["rateLimits": ["primary": ["usedPercent": 150]]]])
        #expect(!invalid.status.isSuccess)
        #expect(invalid.windows.isEmpty)
    }
}

@Suite("AI usage visibility")
struct AIUsageVisibilityTests {
    @Test func onlyShowsSelectedConnectedProviders() {
        let connected = AIProviderUsage(provider: .codex, status: .active, attribution: "test")
        let disconnected = AIProviderUsage(provider: .claudeCode, status: .signedOut("Sign in"), attribution: "test")
        let values: [AIProvider: AIProviderUsage] = [.codex: connected, .claudeCode: disconnected]
        #expect(AIUsageSelection.visible(values, selected: [.claudeCode, .codex]).map(\.provider) == [.codex])
        #expect(AIUsageSelection.visible(values, selected: [.claudeCode]).isEmpty)
        #expect(AIUsageSelection.visible(values, selected: []).isEmpty)
        #expect(AIUsageSelection.visible([:], selected: [.codex]).isEmpty)
    }

    @Test func aiPanelHasRoomForDetails() {
        let engine = LayoutEngine(screen: .sample, appearance: .standard)
        let normal = engine.expandedContentHeight(for: .nook(.home), homeHasMedia: false)!
        let usage = engine.expandedContentHeight(for: .nook(.aiUsage), homeHasMedia: false)!
        #expect(usage > normal)
        #expect(usage == IslandMetrics.Nook.aiUsageBody + IslandMetrics.Nook.bodyTopInset)
        #expect(engine.windowSize.height >= usage)
    }
}
