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
        #expect(!Updater.canReplace(URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Dynamic Notch.app")))
        #expect(!Updater.canReplace(URL(fileURLWithPath: "/Volumes/Dynamic Notch/Dynamic Notch.app")))
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
        #expect(model.launcherItems.count == LauncherItem.allCases.count, "Stats is always there, as a switch")
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
        model.open(.stopwatch)
        #expect(model.presentation == .nook(.timers))
        #expect(model.timerPanelMode == .stopwatch)
        model.open(.keepAwake)
        #expect(model.keepAwake.isOn && model.isLive(.keepAwake))
        model.keepAwake.turnOff()
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
