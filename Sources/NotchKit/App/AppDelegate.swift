import AppKit
import os

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsStore?
    private var model: IslandModel?
    private var islandWindows: IslandWindowManager?
    private var statusController: StatusItemController?
    private var settingsController: SettingsWindowController?
    private var lockScreen: LockScreenController?
    #if DEBUG
    private var openSettingsObserver: NSObjectProtocol?
    private var debugHooks: DebugHooks?
    #endif

    override public init() {
        super.init()
    }

    /// The app has no menu bar of its own (it lives in the notch), and macOS sends Command-C,
    /// Command-V and the rest through an Edit menu. Without one, copy and paste do nothing in
    /// Settings or in Notes. The menu is never shown; its shortcuts are what matter.
    static func installEditMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        main.addItem(appItem)

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // A dead media helper must surface as a write error, not kill the app.
        signal(SIGPIPE, SIG_IGN)
        NSApp.setActivationPolicy(.accessory)
        Self.installEditMenu()

        if terminateIfAlreadyRunning() {
            return
        }
        // 1.3.x updates leave the file named "Dynamic Notch.app"; give it the new name first.
        if AppRename.renameAndRelaunchIfNeeded() {
            return
        }
        AppRename.finishIfRenamed()

        let settings = SettingsStore()
        let model = IslandModel(settings: settings)
        let settingsController = SettingsWindowController(model: model)
        model.onOpenSettings = { [weak settingsController] in settingsController?.show() }
        model.onOpenSettingsTab = { [weak settingsController] tab in settingsController?.show(tab) }
        model.onOpenSoftwareUpdate = { [weak settingsController] in settingsController?.show(.softwareUpdate) }

        self.settings = settings
        self.model = model
        self.settingsController = settingsController
        islandWindows = IslandWindowManager(model: model)
        if LockScreenController.isAvailable { lockScreen = LockScreenController(model: model) }
        statusController = StatusItemController(model: model) { [weak settingsController] in settingsController?.show() }
        #if DEBUG
        // Lets testing scripts open a Settings page. Release builds don't listen for it.
        openSettingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("DynamicNotch.openSettings"),
            object: nil,
            queue: .main
        ) { [weak settingsController] notif in
            let tab = (notif.object as? String).flatMap(Int.init).flatMap(SettingsWindowController.Tab.init(rawValue:))
            MainActor.assumeIsolated {
                settingsController?.show(tab)
            }
        }
        #endif
        let isFirstLaunch = !settings.hasShownWelcome
        model.startServices()
        // The first launch (from Finder or a fresh DMG) shows Home for a moment, so the app
        // doesn't seem to do nothing. Later launches, including at login, stay out of the way.
        if isFirstLaunch { model.showHomeBriefly() }

        #if DEBUG
        debugHooks = DebugHooks(model: model, settings: settingsController, lockScreen: lockScreen)
        #endif
    }

    /// Opening the app again (e.g. from Applications) shows Settings, which is the only way
    /// back when the menu bar icon is hidden.
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsController?.show()
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        model?.tray.endSession()
        model?.stopServices()
        islandWindows?.tearDown()
        lockScreen?.tearDown()
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
