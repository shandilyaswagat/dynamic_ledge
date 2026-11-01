import Foundation
import Testing
@testable import NotchKit

@MainActor
@Suite("AI Agent Usage - Parsing & Windows")
struct AIUsageParsingTests {
    @Test func missingDataDoesNotInventValues() {
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
@Suite("AI Agent Usage - Service Lifecycle")
struct AIUsageServiceTests {
    @Test func automaticRefreshChecksImmediatelyAndStartsOnlyOnce() async throws {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "aiUsage.claudeEnabled")
        defaults.set(false, forKey: "aiUsage.codexEnabled")
        defaults.set(false, forKey: "aiUsage.antigravityEnabled")
        let service = AIUsageService(defaults: defaults)
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
        // Never read this Mac's real assistants in unit tests.
        defaults.set(false, forKey: "aiUsage.claudeEnabled")
        defaults.set(false, forKey: "aiUsage.codexEnabled")
        defaults.set(false, forKey: "aiUsage.antigravityEnabled")
        return defaults
    }

    @Test func manualRefreshCooldownThrottlesRapidRequests() async {
        let defaults = makeDefaults()
        let service = AIUsageService(defaults: defaults)

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
        let restored = AIUsageService(defaults: defaults)

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

@MainActor
@Suite("AI usage privacy")
struct AIUsagePrivacyTests {
    @Test func offUntilTurnedOnAndOldKeysAreErased() {
        let defaults = UserDefaults(suiteName: "AIUsagePrivacy-\(UUID().uuidString)")!
        defaults.set("sk-test", forKey: "aiUsageClaudeApiKey")
        defaults.set("sk-test", forKey: "aiUsageCodexApiKey")
        defaults.set("org-test", forKey: "aiUsageCodexOrgId")
        defaults.set("test", forKey: "aiUsageAntigravityApiKey")
        let settings = SettingsStore(defaults: defaults)
        #expect(!settings.aiUsageEnabled)
        for key in ["aiUsageClaudeApiKey", "aiUsageCodexApiKey", "aiUsageCodexOrgId", "aiUsageAntigravityApiKey"] {
            #expect(defaults.object(forKey: key) == nil)
        }
    }
}
