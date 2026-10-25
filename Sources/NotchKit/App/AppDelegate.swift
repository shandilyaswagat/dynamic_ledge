import AppKit
import os

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsStore?
    private var model: IslandModel?
    private var islandWindows: IslandWindowManager?
    private var statusController: StatusItemController?
    private var settingsController: SettingsWindowController?
    #if DEBUG
    private var debugHooks: DebugHooks?
    #endif

    override public init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // A dead media helper must surface as a write error, not kill the app.
        signal(SIGPIPE, SIG_IGN)
        NSApp.setActivationPolicy(.accessory)

        if terminateIfAlreadyRunning() {
            return
        }

        let settings = SettingsStore()
        let model = IslandModel(settings: settings)
        let settingsController = SettingsWindowController(model: model)
        model.onOpenSettings = { [weak settingsController] in settingsController?.show() }
        model.onOpenAbout = { [weak settingsController] in settingsController?.show(.about) }

        self.settings = settings
        self.model = model
        self.settingsController = settingsController
        islandWindows = IslandWindowManager(model: model)
        statusController = StatusItemController(model: model) { [weak settingsController] in settingsController?.show() }
        model.startServices()

        #if DEBUG
        debugHooks = DebugHooks(model: model, settings: settingsController)
        #endif
    }

    /// Opening the app again (e.g. from Applications) shows Settings, which is the only way
    /// back when the menu bar icon is hidden.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsController?.show()
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        model?.tray.removeAll()
        model?.stopServices()
        islandWindows?.tearDown()
    }

    private func terminateIfAlreadyRunning() -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else { return false }
        Logger(subsystem: Log.subsystem, category: "app").notice("Another copy is running; quitting this one")
        NSApp.terminate(nil)
        return true
    }
}
