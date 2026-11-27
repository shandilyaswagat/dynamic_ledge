import AppKit
import Foundation
import Testing
@testable import NotchKit

@Suite("Versions and releases")
struct VersionTests {
    @Test func comparesNumberByNumber() throws {
        let a = try #require(SemanticVersion("v1.2.0"))
        let b = try #require(SemanticVersion("1.10.0"))
        #expect(a < b)
        #expect(SemanticVersion("1.2") == SemanticVersion("1.2.0"))
        #expect(SemanticVersion("2.0.0-beta.1")?.description == "2.0.0")
        #expect(SemanticVersion("one") == nil)
        #expect(SemanticVersion("1.-2.0") == nil)
    }

    @Test func readsGitHubsLatestRelease() throws {
        let json = """
        {"tag_name":"v1.2.0","html_url":"https://github.com/o/r/releases/tag/v1.2.0","assets":[
          {"name":"DynamicNotch.dmg","browser_download_url":"https://github.com/o/r/releases/download/v1.2.0/DynamicNotch.dmg"},
          {"name":"DynamicNotch.dmg.sha256","browser_download_url":"https://github.com/o/r/releases/download/v1.2.0/DynamicNotch.dmg.sha256"},
          {"name":"DynamicNotch.update.json","browser_download_url":"https://github.com/o/r/releases/download/v1.2.0/DynamicNotch.update.json"}]}
        """
        let release = try #require(ReleaseInfo.parse(Data(json.utf8)))
        #expect(release.version.description == "1.2.0")
        #expect(release.signedManifest?.lastPathComponent == "DynamicNotch.update.json")
        #expect(release.checksum?.lastPathComponent == "DynamicNotch.dmg.sha256")
        #expect(ReleaseInfo.parse(Data(#"{"tag_name":"v1.2.0","assets":[]}"#.utf8)) == nil)
        #expect(ReleaseInfo.parse(Data(#"{"tag_name":"v1.2.0","html_url":"https://attacker.example/release","assets":[{"name":"DynamicNotch.dmg","browser_download_url":"https://attacker.example/DynamicNotch.dmg"}]}"#.utf8)) == nil)
    }

    @Test func neverReplacesATranslocatedCopy() {
        #expect(!Updater.canReplace(URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Dynamic Ledge.app")))
        #expect(!Updater.canReplace(URL(fileURLWithPath: "/Volumes/Dynamic Ledge/Dynamic Ledge.app")))
    }
}

@Suite("Launcher")
struct LauncherTests {
    @Test func everyTileHasItsOwnKey() {
        let keys = LauncherItem.allCases.map(\.key)
        #expect(Set(keys).count == keys.count)
        #expect(LauncherItem.allCases.allSatisfy { HotKeys.keyCode($0.key) != nil })
        #expect(LauncherItem.timer.shortcutLabel == "⌃⌥R")
    }

    @Test func remindersSortOverdueFirst() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let items = [
            ReminderItem(id: "later", title: "Later", due: now.addingTimeInterval(3600)),
            ReminderItem(id: "none", title: "Whenever", due: nil),
            ReminderItem(id: "late", title: "Late", due: now.addingTimeInterval(-3 * 86400)),
        ]
        #expect(ReminderRules.sorted(items).map(\.id) == ["late", "later", "none"])
        #expect(ReminderRules.label(for: items[2], at: now) == "Overdue")
        #expect(ReminderRules.label(for: items[1], at: now) == nil)
    }

    @Test func featureShortcutsAreUniqueAndBounded() {
        var selection = FeatureShortcutSelection(items: [.timer, .timer, .calendar, .files, .stats])
        #expect(selection.items == [.timer, .calendar, .files])
        let addedDuplicate = selection.add(.timer)
        let addedOverCapacity = selection.add(.stats)
        #expect(!addedDuplicate, "a feature is never added twice")
        #expect(!addedOverCapacity, "three custom slots are the limit")
        let removed = selection.remove(.timer)
        let added = selection.add(.stats)
        #expect(removed)
        #expect(added)
        #expect(selection.items == [.calendar, .files, .stats], "a new one goes last")

        let restored = FeatureShortcutSelection(rawValues: ["calendar", "missing", "calendar", "files"])
        #expect(restored.items == [.calendar, .files])
    }
}

@MainActor
@Suite("Launcher in the model")
struct LauncherModelTests {
    private func makeModel() -> IslandModel {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        return IslandModel(
            settings: SettingsStore(defaults: defaults),
            tray: TrayStore(folder: nil),
            clipboard: ClipboardMonitor(pasteboard: NSPasteboard(name: NSPasteboard.Name("NotchTests-\(UUID().uuidString)"))),
            notes: NotesStore(defaults: defaults)
        )
    }

    @Test func tilesFollowSettings() {
        let model = makeModel()
        #expect(model.launcherItems.count == LauncherItem.allCases.count - 1, "Stats is always there, as a switch")
        #expect(!model.launcherItems.contains(.aiUsage), "AI Agent Usage stays hidden until it's turned on")
        model.settings.aiUsageEnabled = true
        #expect(model.launcherItems.contains(.aiUsage))
        model.settings.clipboardEnabled = false
        model.settings.mirrorEnabled = false
        #expect(!model.launcherItems.contains(.clipboard))
        #expect(!model.launcherItems.contains(.mirror))
        #expect(model.launcherItems.contains(.keepAwake))
    }

    @Test func tilesOpenTheirViews() {
        let model = makeModel()
        model.showTab(.launcher)
        #expect(model.presentation == .nook(.launcher))
        model.open(.files)
        #expect(model.presentation == .tray)
        model.open(.scratchpad)
        #expect(model.presentation == .notes)
        model.open(.reminders)
        #expect(model.presentation == .nook(.reminders))
        #expect(model.launcherItems.contains(.bluetooth))
        #expect(model.addFeatureShortcut(.bluetooth))
        #expect(model.featureShortcuts.contains(.bluetooth))
        model.open(.bluetooth)
        #expect(model.presentation == .nook(.bluetooth))
        model.open(.stopwatch)
        #expect(model.presentation == .nook(.timers))
        #expect(model.timerPanelMode == .stopwatch)
        model.open(.keepAwake)
        #expect(model.keepAwake.isOn && model.isLive(.keepAwake))
        model.keepAwake.turnOff()
    }

    @Test func homeDashboardPersistsCardOrderAndSamplesStatsOnlyWhenShown() throws {
        let defaults = try #require(UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)"))
        let settings = SettingsStore(defaults: defaults)
        let model = IslandModel(settings: settings, tray: TrayStore(folder: nil))

        model.showTab(.home)
        model.editHomeDashboard()
        let engine = LayoutEngine(screen: .sample, appearance: .standard)
        let compactHeight = engine.expandedContentHeight(for: .nook(.home), home: model.homeContent)
        #expect(model.homeContent.dashboardRows == 1)
        model.setHomeDashboardDragging(true)
        #expect(model.homeContent.dashboardRows == 2)
        let dragHeight = try #require(engine.expandedContentHeight(for: .nook(.home), home: model.homeContent))
        #expect(dragHeight > (compactHeight ?? 0))
        model.setHomeDashboardDragging(false)
        #expect(engine.expandedContentHeight(for: .nook(.home), home: model.homeContent) == compactHeight)
        model.setHomeDashboardEditorMode(.choosing)
        #expect(model.homeContent.dashboardRows == 2)
        model.setHomeDashboardDragging(false)
        #expect(model.homeDashboardEditorMode == .choosing)
        model.finishEditingHomeDashboard()
        #expect(model.homeDashboardEditorMode == .arranging)
        #expect(settings.homeDashboard == nil)

        model.editHomeDashboard()
        model.updateHomeDashboard {
            // Six fixed slots, as earlier builds saved them, become cards a third of Home wide.
            $0 = HomeDashboardLayout(rawValues: ["stats", "bluetooth", "", "", "calendar", ""])
            #expect($0.rawValues == ["stats:0:0:2:1", "bluetooth:2:0:2:1", "calendar:2:1:2:1"])
            $0.move(.calendar, toColumn: 9, row: 0)
            $0.resize(.calendar, width: 2, height: 2)
            // A card dropped onto another trades places with it.
            $0.move(.stats, toColumn: 2, row: 0)
            #expect($0.rawValues == ["stats:2:0:2:1", "bluetooth:0:0:2:1", "calendar:4:0:2:2"])
            $0.add(.stats)
            $0.add(.timer)
            #expect($0.card(for: .timer) == HomeDashboardCard(widget: .timer, column: 0, row: 1, width: 2, height: 1))
            $0.remove(.timer)
            // A card grown over others pushes them to the nearest room, smaller if need be.
            $0.resize(.bluetooth, width: 9, height: 1)
            // With nowhere for the others to go, nothing moves.
            let grewWithNoRoom = $0.resize(.bluetooth, width: 6, height: 2)
            #expect(!grewWithNoRoom)
        }
        let arranged = ["stats:2:1:2:1", "bluetooth:0:0:6:1", "calendar:4:1:2:1"]
        #expect(settings.homeDashboard?.rawValues == arranged)
        #expect(model.homeContent.isEditingDashboard)
        model.finishEditingHomeDashboard()
        #expect(model.stats.isRunning && !settings.statsEnabled)
        // A Stats card can be made wide enough for disk and network, so those are read too.
        #expect(model.stats.detailed)
        #expect(model.homeContent.dashboardRows == 2)
        #expect(SettingsStore(defaults: defaults).homeDashboard == settings.homeDashboard)

        // Each step of a drag starts from the layout it began with, so a card carried back
        // to where it started has to count as placed, and put the others back with it.
        let start = HomeDashboardLayout(rawValues: arranged)
        var dragged = start
        #expect(dragged.move(.stats, toColumn: 4, row: 1) && dragged != start)
        dragged = start
        #expect(dragged.move(.stats, toColumn: 2, row: 1) && dragged == start)

        // Home closes up empty rows while keeping saved columns.
        let sparse = HomeDashboardLayout(rawValues: ["music:0:1:2:1", "calendar:4:1:2:1"])
        let frames = sparse.frames(in: 208, rowHeight: 100, gap: 8, presentation: .home)
        #expect(frames[.music] == CGRect(x: 0, y: 0, width: 64, height: 100))
        #expect(frames[.calendar] == CGRect(x: 144, y: 0, width: 64, height: 100))

        model.showTab(.clipboard)
        #expect(!model.stats.isRunning && !model.stats.detailed)
        model.showTab(.home)
        model.editHomeDashboard()
        model.updateHomeDashboard { $0 = sparse }
        #expect(model.homeContent.dashboardRows == 2)
        model.finishEditingHomeDashboard()
        #expect(model.homeContent.dashboardRows == 1)
        model.editHomeDashboard()
        model.updateHomeDashboard { $0 = HomeDashboardLayout() }
        #expect(SettingsStore(defaults: defaults).homeDashboard?.widgets == [])
        model.resetHomeDashboard()
        #expect(SettingsStore(defaults: defaults).homeDashboard == nil)
        model.setHomeDashboardDragging(true)
        model.collapse()
        #expect(model.homeDashboardDraft == nil)
        #expect(model.homeDashboardEditorMode == .arranging)
    }

    @Test func homeDashboardKeepsSavedColumnsAroundSpanningCards() {
        let layout = HomeDashboardLayout(rawValues: ["stats:0:0:6:1", "music:0:1:2:1", "timer:2:1:2:1"])
        let home = layout.frames(in: 472, rowHeight: 100, gap: 8, presentation: .home)
        #expect(home[.stats] == CGRect(x: 0, y: 0, width: 472, height: 100))
        #expect(home[.music] == CGRect(x: 0, y: 108, width: 152, height: 100))
        #expect(home[.timer] == CGRect(x: 160, y: 108, width: 152, height: 100))

        let spanning = HomeDashboardLayout(rawValues: ["stats:2:0:2:2", "music:0:0:2:1", "timer:4:1:2:1"])
        let frames = spanning.frames(in: 472, rowHeight: 100, gap: 8, presentation: .home)
        #expect(frames[.stats] == CGRect(x: 160, y: 0, width: 152, height: 208))
        #expect(frames[.music]?.maxX == 152)
        #expect(frames[.timer]?.minX == 320)
    }

    @Test func homeDashboardEditorKeepsCardWidthAfterResize() {
        var layout = HomeDashboardLayout(rawValues: ["music:0:0:4:1"])
        let resized = layout.resize(.music, width: 2, height: 1)
        #expect(resized)
        let frames = layout.frames(in: 472, rowHeight: 100, gap: 8, presentation: .editor)
        #expect(frames[.music] == CGRect(x: 0, y: 0, width: 152, height: 100))
    }

    @Test func homeDashboardTriesAlternatePlacementsForDisplacedCards() {
        var layout = HomeDashboardLayout(rawValues: ["music:0:0:2:1", "calendar:2:0:3:2", "stats:0:1:2:1"])
        let resized = layout.resize(.music, width: 4, height: 2)
        #expect(resized)
        #expect(layout.rawValues == ["music:0:0:4:2", "calendar:4:0:2:1", "stats:4:1:2:1"])
    }

    @Test func homeDashboardSkipsInvalidRecordsAndLoadsLegacySlots() {
        let layout = HomeDashboardLayout(rawValues: [
            "music:\(Int.max):0:2:1", "calendar:0:0:\(Int.max):1", "stats:bad",
            "aiUsage:0::0:2:1", "shortcuts:0:0:2:1:bad", "bluetooth"
        ])
        #expect(layout.rawValues == ["bluetooth:4:1:2:1"])
    }

    @Test func featureShortcutsPersistAndOpenTheSameFeatures() {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        #expect(!settings.hasCustomizedFeatureShortcuts)
        #expect(settings.featureShortcuts == [.files, .clipboard])

        // Add third item to reach limit
        #expect(settings.addFeatureShortcut(.calendar))
        #expect(settings.hasCustomizedFeatureShortcuts)
        #expect(!settings.addFeatureShortcut(.timer))
        #expect(settings.featureShortcuts == [.files, .clipboard, .calendar])

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.hasCustomizedFeatureShortcuts)
        #expect(reloaded.featureShortcuts == [.files, .clipboard, .calendar])

        let model = IslandModel(settings: reloaded, tray: TrayStore(folder: nil))
        model.open(reloaded.featureShortcuts[0])
        #expect(model.presentation == .tray)
        model.open(reloaded.featureShortcuts[2])
        #expect(model.presentation == .nook(.calendar))

        // Edit, in the grid, ends whenever something else opens.
        model.showTab(.launcher)
        model.isEditingShortcuts = true
        model.showTab(.home)
        #expect(!model.isEditingShortcuts)
        model.showTab(.launcher)
        #expect(!model.isEditingShortcuts, "the grid reopens normally")
        model.isEditingShortcuts = true
        model.collapse()
        #expect(!model.isEditingShortcuts)
    }

    @Test func editingShortcutsLimitsAndInteractions() {
        let defaults = UserDefaults(suiteName: "NotchTests-Edit-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        let model = IslandModel(settings: settings, tray: TrayStore(folder: nil))

        #expect(!model.isEditingShortcuts)
        model.isEditingShortcuts = true
        #expect(model.isEditingShortcuts)

        // Starting with default shortcuts
        #expect(model.settings.featureShortcuts == [.files, .clipboard])

        // Adding shortcut up to maximum of 3
        #expect(model.settings.addFeatureShortcut(.calendar))
        // Duplicate is rejected
        #expect(!model.settings.addFeatureShortcut(.files))
        // At limit of 3
        #expect(model.settings.featureShortcuts.count == 3)
        #expect(!model.settings.addFeatureShortcut(.stats), "further additions disabled at capacity")

        // Removing enables addition immediately
        #expect(model.settings.removeFeatureShortcut(.files))
        #expect(model.settings.featureShortcuts.count == 2)
        #expect(model.settings.addFeatureShortcut(.stats), "additions re-enabled after removal")
        #expect(model.settings.featureShortcuts == [.clipboard, .calendar, .stats])

        // Exiting edit mode
        model.isEditingShortcuts = false
        #expect(!model.isEditingShortcuts)

        // Navigation to original view and back to Home
        model.open(.calendar)
        #expect(model.presentation == .nook(.calendar))
        model.showTab(.home)
        #expect(model.presentation == IslandPresentation.home)
    }

    @Test func cameraMirrorOffOption() {
        let camera = CameraAccess()
        #expect(!camera.isCameraOff)
        camera.toggleCamera()
        #expect(camera.isCameraOff)
        camera.toggleCamera()
        #expect(!camera.isCameraOff)
    }

    @Test func trayItemRemovalAndClear() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file1 = tempDir.appendingPathComponent("document1.pdf")
        let file2 = tempDir.appendingPathComponent("image2.png")
        try Data("test1".utf8).write(to: file1)
        try Data("test2".utf8).write(to: file2)

        let tray = TrayStore(folder: tempDir)
        let added = tray.add([file1, file2])
        #expect(added == 2)
        #expect(tray.items.count == 2)

        let firstId = tray.items[0].id
        tray.remove(firstId)
        #expect(tray.items.count == 1)
        #expect(tray.items[0].id != firstId)

        tray.removeAll()
        #expect(tray.items.isEmpty)
    }

    @Test func screensWithoutANotchGetAVirtualNotch() {
        let model = makeModel()
        model.screen = ScreenMetrics(size: CGSize(width: 2560, height: 1440), notch: nil, menuBarHeight: 25)
        #expect(model.engine.isVirtualNotch)
        model.screen = .sample
        #expect(!model.engine.isVirtualNotch)
    }
}

@Suite("Renaming to Dynamic Ledge")
struct AppRenameTests {
    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func anUpdatedOldCopyGetsTheNewName() throws {
        let apps = try folder()
        defer { try? FileManager.default.removeItem(at: apps) }
        let old = apps.appendingPathComponent("Dynamic Notch.app")
        #expect(AppRename.destination(for: old) == apps.appendingPathComponent("Dynamic Ledge.app"))
    }

    @Test func leavesEverythingElseAlone() throws {
        let apps = try folder()
        defer { try? FileManager.default.removeItem(at: apps) }
        #expect(AppRename.destination(for: apps.appendingPathComponent("Dynamic Ledge.app")) == nil, "already renamed")
        #expect(AppRename.destination(for: URL(fileURLWithPath: "/Volumes/Dynamic Notch/Dynamic Notch.app")) == nil, "disk image")

        let old = apps.appendingPathComponent("Dynamic Notch.app")
        try FileManager.default.createDirectory(at: apps.appendingPathComponent("Dynamic Ledge.app"), withIntermediateDirectories: true)
        #expect(AppRename.destination(for: old) == nil, "never over another copy")
    }
}
