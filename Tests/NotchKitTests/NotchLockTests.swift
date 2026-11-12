import AppKit
import Observation
import Testing
@testable import NotchKit

@MainActor
@Suite("Notch lock")
struct NotchLockTests {
    private func model() -> IslandModel {
        let defaults = UserDefaults(suiteName: "NotchLock-\(UUID().uuidString)")!
        return IslandModel(settings: SettingsStore(defaults: defaults),
            aiUsage: AIUsageService(defaults: defaults, reader: { .unconfigured(for: $0) }))
    }

    @Test func lockKeepsOutsideClicksOpenButExplicitCloseWorks() {
        let model = model()
        model.expand(.home)
        model.toggleNotchLock()
        model.outsideClick()
        #expect(model.expandTarget != nil)
        #expect(model.isNotchLocked)
        model.collapse()
        #expect(model.expandTarget == nil)
        #expect(!model.isNotchLocked)
    }

    @Test func disablingControlReleasesLockAndPersists() {
        let model = model()
        model.expand(.home)
        model.toggleNotchLock()
        model.settings.showNotchLock = false
        model.outsideClick()
        #expect(model.expandTarget == nil)
        #expect(!SettingsStore(defaults: model.settings.defaults).showNotchLock)
        model.expand(.home)
        model.toggleNotchLock()
        #expect(!model.isNotchLocked)
    }

    @Test func lockedPointerExitStaysOpenThenUnlockAllowsCollapse() async throws {
        let model = model()
        model.expand(.home)
        model.toggleNotchLock()
        model.pointerMoved(to: CGPoint(x: model.layout.pill.midX, y: model.layout.pill.midY))
        model.pointerMoved(to: nil)
        // Exercise the delayed dismissal callback while locked.
        try await Task.sleep(for: .milliseconds(1100))
        #expect(model.expandTarget != nil)
        model.toggleNotchLock()
        model.pointerMoved(to: CGPoint(x: model.layout.pill.midX, y: model.layout.pill.midY))
        model.pointerMoved(to: nil)
        let deadline = Date().addingTimeInterval(3)
        while model.expandTarget != nil && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(model.expandTarget == nil)
    }
}

@MainActor
@Suite("Automatic remaining allowance")
struct AutomaticAllowanceTests {
    @Test func discoversSupportedProvidersWithoutClaude() async throws {
        let defaults = UserDefaults(suiteName: "AutomaticAllowance-\(UUID().uuidString)")!
        var requested: [AIProvider] = []
        let service = AIUsageService(defaults: defaults, reader: { provider in
            requested.append(provider)
            return AIProviderUsage(provider: provider, status: .active,
                windows: [AIUsageWindow(name: "Plan", usedPercent: 25, sourceDescription: "Test")],
                lastUpdated: Date(), attribution: "Test")
        })
        service.refreshAll()
        let deadline = Date().addingTimeInterval(3)
        while service.isRefreshing && Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(requested == [.codex, .antigravity])
        #expect(service.minimumRemainingPercent == 75)
        #expect(service.usages[.claudeCode] == nil)
        service.refreshAll()
        #expect(!service.isRefreshing)
    }
}
