import Foundation
import Testing
@testable import NotchKit

@MainActor
private func makeDefaults() -> UserDefaults {
    let name = "NotchKitTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
@Suite("Settings store")
struct SettingsStoreTests {
    @Test func defaults() {
        let store = SettingsStore(defaults: makeDefaults())
        #expect(store.appearance == .standard)
        #expect(store.collapseOnPointerExit)
        #expect(!store.showWhenIdle)
        #expect(store.notchOpenMode == .click)
        #expect(store.nowPlayingEnabled && store.timerEnabled && store.callsEnabled && store.airDropEnabled)
        #expect(store.pausedMediaLinger == 30)
        #expect(store.display == .automatic)
    }

    @Test func persistsAcrossLaunches() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.appearance.width = 300
        store.appearance.style = .island
        store.appearance.pitchBlack = false
        store.showWhenIdle = true
        store.display = .main
        store.notchOpenMode = .hover
        store.pausedMediaLinger = 300
        store.callsEnabled = false

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.appearance.width == 300)
        #expect(reloaded.appearance.style == .island)
        #expect(!reloaded.appearance.pitchBlack)
        #expect(reloaded.showWhenIdle)
        #expect(reloaded.display == .main)
        #expect(reloaded.notchOpenMode == .hover)
        #expect(reloaded.pausedMediaLinger == 300)
        #expect(!reloaded.callsEnabled)
    }

    @Test func badStoredValuesFallBack() {
        let defaults = makeDefaults()
        defaults.set(99_999.0, forKey: "shape.width")
        defaults.set("sideways", forKey: "shape.style")
        defaults.set("moon", forKey: "general.display")
        defaults.set(7.0, forKey: "nowPlaying.pausedLinger")
        let store = SettingsStore(defaults: defaults)
        #expect(store.appearance.width == NotchAppearance.widthRange.upperBound)
        #expect(store.appearance.style == .notch)
        #expect(store.display == .automatic)
        #expect(store.pausedMediaLinger == 30)
    }

    @Test func migratesTheLegacyHoverSetting() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "behavior.expandOnHover")
        #expect(SettingsStore(defaults: defaults).notchOpenMode == .hover)
        defaults.set("click", forKey: "behavior.notchOpenMode")
        #expect(SettingsStore(defaults: defaults).notchOpenMode == .click)
    }

    @Test func resetAppearance() {
        let store = SettingsStore(defaults: makeDefaults())
        store.appearance.height = 50
        store.resetAppearance()
        #expect(store.appearance == .standard)
    }
}

/// A clock the tests move by hand.
@MainActor
private final class TestClock {
    var now = Date(timeIntervalSince1970: 10_000)
}

@MainActor
@Suite("Timer service")
struct TimerServiceTests {
    @Test func finishesOnceAndRepeats() {
        let clock = TestClock()
        let service = TimerService(now: { clock.now })
        var finishes = 0
        service.onFinish = { finishes += 1 }

        service.start(duration: 60)
        #expect(service.isActive)
        clock.now += 30
        service.checkCompletion()
        #expect(finishes == 0)
        clock.now += 30
        service.checkCompletion()
        service.checkCompletion()
        #expect(finishes == 1)
        #expect(!service.isActive)
        #expect(service.timer?.isFinished == true)

        service.repeatLast()
        #expect(service.isActive)
        #expect(service.timer?.remaining(at: clock.now) == 60)
        service.cancel()
        #expect(service.timer == nil)
    }

    @Test func pausedTimerNeverFinishes() {
        let clock = TestClock()
        let service = TimerService(now: { clock.now })
        var finished = false
        service.onFinish = { finished = true }
        service.start(duration: 10)
        service.togglePause()
        clock.now += 100
        service.checkCompletion()
        #expect(!finished)
        service.togglePause()
        #expect(service.timer?.remaining(at: clock.now) == 10)
    }
}

@MainActor
@Suite("Island model")
struct IslandModelTests {
    private func makeModel() -> IslandModel {
        let model = IslandModel(settings: SettingsStore(defaults: makeDefaults()), tray: TrayStore(folder: nil))
        model.screen = .sample
        return model
    }

    @Test func startsHidden() {
        #expect(makeModel().presentation == .hidden(peek: false))
    }

    @Test func timerShowsCompactThenExpands() {
        let model = makeModel()
        model.startTimer(300)
        #expect(model.presentation == .compact(primary: .timer, secondary: nil))
        model.tapPill()
        #expect(model.presentation == .expanded(.timer))
        model.outsideClick()
        #expect(model.presentation == .compact(primary: .timer, secondary: nil))
    }

    @Test func clickingTheNotchOpensHome() {
        let model = makeModel()
        model.tapPill()
        #expect(model.presentation == .home)
        model.collapse()
        #expect(model.presentation == .hidden(peek: false))
    }

    @Test func alertsWaitForExpandedViewsExceptTimerDone() {
        let model = makeModel()
        model.expand(.home)
        model.receive(.charging(level: 50, isCharging: true))
        #expect(model.presentation == .home, "non-urgent alert waits")
        model.collapse()
        #expect(model.presentation == .alert(.charging(level: 50, isCharging: true)))
        model.dismissAlert()
        #expect(model.presentation == .hidden(peek: false))

        model.expand(.home)
        model.receive(.timerFinished)
        #expect(model.presentation == .alert(.timerFinished), "timer done interrupts")
        model.stopTimerAlarm()
        #expect(model.presentation == .home)
    }

    @Test func disabledAlertsAreDropped() {
        let model = makeModel()
        model.settings.chargingAlertsEnabled = false
        model.receive(.charging(level: 50, isCharging: true))
        #expect(model.presentation == .hidden(peek: false))
        model.settings.headphoneAlertsEnabled = false
        model.receive(.headphones(name: "AirPods", symbol: "airpods"))
        #expect(model.presentation == .hidden(peek: false))
    }

    @Test func disabledActivitiesDisappear() {
        let model = makeModel()
        model.startTimer(60)
        model.settings.timerEnabled = false
        #expect(model.presentation == .hidden(peek: false))
    }

    @Test func hoveringTheNotchPeeksAndTakesTheMouse() throws {
        let model = makeModel()
        let notch = try #require(model.engine.notchInWindow)
        #expect(model.pointerMoved(to: CGPoint(x: notch.midX, y: 10)))
        #expect(model.presentation == .hidden(peek: true))
        #expect(!model.pointerMoved(to: CGPoint(x: notch.midX, y: 200)))
        #expect(model.presentation == .hidden(peek: false))
        #expect(!model.pointerMoved(to: nil))
    }

    @Test func clickModeNeverOpensOnlyFromHover() async throws {
        let model = makeModel()
        let notch = try #require(model.engine.notchInWindow)
        #expect(model.settings.notchOpenMode == .click)
        _ = model.pointerMoved(to: CGPoint(x: notch.midX, y: 10))
        try await Task.sleep(for: .milliseconds(1200))
        #expect(model.presentation == .hidden(peek: true))
    }

    @Test func hoverModeOpensWithoutAClick() async throws {
        let model = makeModel()
        let notch = try #require(model.engine.notchInWindow)
        model.settings.notchOpenMode = .hover
        _ = model.pointerMoved(to: CGPoint(x: notch.midX, y: 10))
        try await Task.sleep(for: .milliseconds(1200))
        #expect(model.presentation == .home)
    }

    @Test func hoveringTheCompactShapeLiftsIt() {
        let model = makeModel()
        model.startTimer(60)
        let rest = model.layout
        #expect(model.pointerMoved(to: CGPoint(x: rest.pill.midX, y: rest.pill.midY)))
        #expect(model.isHoveringPill)
        #expect(model.layout.pill.width > rest.pill.width)
        #expect(!model.pointerMoved(to: CGPoint(x: 5, y: 300)))
        #expect(!model.isHoveringPill)
    }

    @Test func fileDragNearTheNotchBecomesADropTarget() {
        let model = makeModel()
        let zone = model.engine.dropZone
        model.fileDragChanged(isDragging: true, at: CGPoint(x: zone.midX, y: 5))
        #expect(model.presentation == .drop(targeted: false))
        #expect(model.pointerMoved(to: CGPoint(x: 1, y: 1)), "window takes the mouse during a drag")
        model.fileDragChanged(isDragging: true, at: CGPoint(x: zone.maxX + 50, y: zone.maxY + 50))
        #expect(model.presentation == .hidden(peek: false))
        model.settings.airDropEnabled = false
        model.fileDragChanged(isDragging: true, at: CGPoint(x: zone.midX, y: 5))
        #expect(model.presentation == .drop(targeted: false), "the tray still takes files")
        model.settings.trayEnabled = false
        model.fileDragChanged(isDragging: true, at: CGPoint(x: zone.midX, y: 5))
        #expect(model.presentation == .hidden(peek: false))
    }

    @Test func swipingSwapsActivitiesOnlyWhenThereAreTwo() {
        let model = makeModel()
        model.startTimer(60)
        model.cyclePrimary(forward: true)
        #expect(model.presentation == .compact(primary: .timer, secondary: nil))
    }

    @Test func previewShowsTheShape() {
        let model = makeModel()
        model.isPreviewing = true
        #expect(model.presentation == .idle)
    }
}
