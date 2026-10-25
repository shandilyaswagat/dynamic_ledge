import AppKit
import Observation

/// Owns the notch windows: one that follows the Display setting, or, with "All displays", one per
/// connected screen. Rebuilds them when that setting or the set of screens changes.
@MainActor
public final class IslandWindowManager {
    private let model: IslandModel
    private var controllers: [IslandWindowController] = []
    private var builtFor: (choice: DisplayChoice, screens: [UInt32])?
    private var observer: NSObjectProtocol?

    public init(model: IslandModel) {
        self.model = model
        rebuildIfNeeded()
        observeSettings()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildIfNeeded() }
        }
    }

    public func tearDown() {
        controllers.forEach { $0.tearDown() }
        controllers.removeAll()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func rebuildIfNeeded() {
        let choice = model.settings.display
        let screens = NSScreen.screens.map(IslandWindowController.displayID)
        if choice == .all {
            guard builtFor?.choice != .all || builtFor?.screens != screens else { return }
            controllers.forEach { $0.tearDown() }
            // Start on the built-in screen, or keep the screen in use if it's still connected.
            if !screens.contains(model.activeDisplayID), let start = IslandWindowController.builtIn {
                model.useOnly(display: IslandWindowController.displayID(start), metrics: ScreenMetrics(screen: start))
            }
            controllers = screens.map { IslandWindowController(model: model, displayID: $0) }
        } else {
            // The single window follows the setting and screen changes by itself.
            guard builtFor == nil || builtFor?.choice == .all else {
                builtFor = (choice, screens)
                return
            }
            controllers.forEach { $0.tearDown() }
            controllers = [IslandWindowController(model: model)]
        }
        builtFor = (choice, screens)
    }

    private func observeSettings() {
        withObservationTracking {
            _ = model.settings.display
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.rebuildIfNeeded()
                self?.observeSettings()
            }
        }
    }
}
