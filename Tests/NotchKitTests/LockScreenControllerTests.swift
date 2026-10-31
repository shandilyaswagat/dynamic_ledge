import AppKit
import Testing
@testable import NotchKit

@MainActor
private final class LockScreenPresenterSpy: LockScreenPresenting {
    var visible = false
    var events: [String] = []

    func show() {
        visible = true
        events.append("show")
    }

    func hide() {
        visible = false
        events.append("hide")
    }
}

@MainActor
@Suite("Lock Screen lifecycle")
struct LockScreenControllerTests {
    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
        }
        return condition()
    }

    @Test func switchesAndContentChangesTakeEffectWhileLocked() async {
        let name = "LockScreenLifecycle-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = IslandModel(settings: SettingsStore(defaults: defaults))
        let presenter = LockScreenPresenterSpy()
        let notifications = NotificationCenter()
        let controller = LockScreenController(model: model, presenter: presenter,
                                              lockNotifications: notifications, screenNotifications: notifications,
                                              initiallyLocked: false)
        defer { controller.tearDown(); model.timer.cancel() }
        model.timer.start(duration: 60)
        notifications.post(name: .init("com.apple.screenIsLocked"), object: nil)
        #expect(!presenter.visible)

        model.settings.lockScreenEnabled = true
        #expect(await waitUntil { presenter.visible })
        model.settings.lockScreenTimersEnabled = false
        #expect(await waitUntil { !presenter.visible })
        model.settings.lockScreenTimersEnabled = true
        #expect(await waitUntil { presenter.visible })
        model.timer.cancel()
        #expect(await waitUntil { !presenter.visible })
        model.timer.start(duration: 60)
        #expect(await waitUntil { presenter.visible })
        model.settings.lockScreenEnabled = false
        #expect(await waitUntil { !presenter.visible })
        model.settings.lockScreenEnabled = true
        #expect(await waitUntil { presenter.visible })

        notifications.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
        #expect(!presenter.visible)
    }

    @Test func launchWhileLockedAndDisplayChangesUseCurrentContent() {
        let name = "LockScreenStartup-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = IslandModel(settings: SettingsStore(defaults: defaults))
        model.settings.lockScreenEnabled = true
        model.timer.start(duration: 60)
        let presenter = LockScreenPresenterSpy()
        let notifications = NotificationCenter()
        let controller = LockScreenController(model: model, presenter: presenter,
                                              lockNotifications: notifications, screenNotifications: notifications,
                                              initiallyLocked: true)
        defer { controller.tearDown(); model.timer.cancel() }
        #expect(presenter.visible)
        presenter.events.removeAll()
        notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(presenter.events == ["hide", "show"])
        notifications.post(name: .init("com.apple.screenIsUnlocked"), object: nil)
        presenter.events.removeAll()
        notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        #expect(!presenter.events.contains("show"))
    }

    @Test func queuedSettingsChangesCannotReopenAfterTeardown() async {
        let name = "LockScreenShutdown-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        let model = IslandModel(settings: settings)
        model.timer.start(duration: 60)
        defer { model.timer.cancel() }
        let presenter = LockScreenPresenterSpy()
        let notifications = NotificationCenter()
        let controller = LockScreenController(model: model, presenter: presenter,
                                              lockNotifications: notifications, screenNotifications: notifications,
                                              initiallyLocked: true)
        // This queues an observation callback without giving it a turn on the main actor.
        settings.lockScreenEnabled = true
        controller.tearDown()
        let eventsAtShutdown = presenter.events
        // A second live observer provides a positive signal that settings callbacks have run.
        let probe = LockScreenPresenterSpy()
        let live = LockScreenController(model: model, presenter: probe,
                                       lockNotifications: NotificationCenter(), screenNotifications: NotificationCenter(),
                                       initiallyLocked: true)
        defer { live.tearDown() }
        settings.lockScreenEnabled = false
        #expect(await waitUntil { !probe.visible })
        settings.lockScreenEnabled = true
        #expect(await waitUntil { probe.visible })
        notifications.post(name: .init("com.apple.screenIsLocked"), object: nil)
        notifications.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        controller.tearDown()
        #expect(!presenter.visible)
        #expect(presenter.events == eventsAtShutdown)
    }
}
