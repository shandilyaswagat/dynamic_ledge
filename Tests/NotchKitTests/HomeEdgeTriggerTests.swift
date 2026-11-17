import Foundation
import Testing
@testable import NotchKit

@Suite("Home edge triggers")
struct HomeEdgeTriggerTests {
    @Test(arguments: [CGSize(width: 1512, height: 982), CGSize(width: 2560, height: 1440)])
    func usesSmallTargetsAtTheEdges(size: CGSize) {
        var target = HomeEdgeTrigger()
        #expect(target.enter(at: CGPoint(x: 1, y: 4), on: size) == nil)
        #expect(target.enter(at: CGPoint(x: 1, y: 1), on: size) == .topLeft)
        #expect(target.enter(at: CGPoint(x: size.width - 5, y: 1), on: size) == nil)
        #expect(target.enter(at: CGPoint(x: size.width - 4, y: 1), on: size) == .topRight)
        #expect(target.enter(at: CGPoint(x: size.width, y: 1), on: size) == nil)
        #expect(target.enter(at: CGPoint(x: size.width / 2, y: 2), on: size) == nil)
        #expect(target.enter(at: CGPoint(x: size.width / 2, y: 1), on: size) == .topCenter)
        #expect(target.enter(at: CGPoint(x: size.width / 2, y: 0), on: size) == nil)
        #expect(target.enter(at: CGPoint(x: size.width / 2, y: size.height - 2), on: size) == nil)
        #expect(target.enter(at: CGPoint(x: size.width / 2 + 50, y: size.height - 1), on: size) == nil)
        #expect(target.enter(at: CGPoint(x: size.width / 2, y: size.height - 1), on: size) == .bottomCenter)
        #expect(target.enter(at: CGPoint(x: size.width / 2, y: size.height + 1), on: size) == nil)
    }

    @Test func eachTriggerRearmsOnlyAfterLeaving() {
        let size = CGSize(width: 1200, height: 800)
        var target = HomeEdgeTrigger()
        #expect(target.enter(at: CGPoint(x: 2, y: 2), on: size) == .topLeft)
        #expect(target.enter(at: CGPoint(x: 1, y: 1), on: size) == nil)
        #expect(target.enter(at: CGPoint(x: 10, y: 10), on: size) == nil)
        #expect(target.enter(at: CGPoint(x: 2, y: 2), on: size) == .topLeft)
        #expect(target.enter(at: CGPoint(x: 1198, y: 2), on: size) == .topRight)
        #expect(target.enter(at: CGPoint(x: 1199, y: 1), on: size) == nil)
        #expect(target.enter(at: CGPoint(x: 600, y: 799), on: size) == .bottomCenter)
        #expect(target.enter(at: CGPoint(x: 602, y: 800), on: size) == nil)
    }
}

@MainActor
@Suite("Home opened from a display edge")
struct HomeEdgeModelTests {
    @Test func exactlyOneOpeningMethodIsSaved() {
        let suite = "HomeEdgeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.notchOpenMode == .click)
        for mode in NotchOpenMode.allCases {
            settings.notchOpenMode = mode
            #expect(SettingsStore(defaults: defaults).notchOpenMode == mode)
        }
    }

    @Test func legacyEdgeSwitchesMigrateOnce() {
        let suite = "HomeEdgeMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "behavior.topLeftHomeTrigger")
        defaults.set(true, forKey: "behavior.topRightHomeTrigger")
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.notchOpenMode == .topLeft)
        settings.notchOpenMode = .hover
        #expect(SettingsStore(defaults: defaults).notchOpenMode == .hover)
        #expect(defaults.object(forKey: "behavior.topLeftHomeTrigger") == nil)
        #expect(defaults.object(forKey: "behavior.topRightHomeTrigger") == nil)
    }

    @Test func edgeOpeningDoesNotAlsoOpenByClick() {
        let suite = "HomeEdgeClick.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = IslandModel(settings: SettingsStore(defaults: defaults), tray: TrayStore(folder: nil, defaults: nil))
        model.useOnly(display: 1, metrics: .sample)
        model.settings.notchOpenMode = .topCenter
        model.tapPill()
        #expect(model.expandTarget == nil)
        #expect(model.openHomeFromEdge(on: 1, metrics: .sample))
        model.collapse()
        model.settings.notchOpenMode = .click
        model.tapPill()
        #expect(model.expandTarget == .home)
    }

    @Test func openingSelectsTheTriggerDisplayAndLeavesExistingPanelsInPlace() {
        let suite = "HomeEdgeModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = IslandModel(settings: SettingsStore(defaults: defaults), tray: TrayStore(folder: nil, defaults: nil))
        model.useOnly(display: 1, metrics: .sample)
        #expect(model.openHomeFromEdge(on: 2, metrics: .sample))
        #expect(model.activeDisplayID == 2 && model.expandTarget == .home)
        #expect(!model.openHomeFromEdge(on: 1, metrics: .sample))
        #expect(model.activeDisplayID == 2 && model.expandTarget == .home)
    }
}
