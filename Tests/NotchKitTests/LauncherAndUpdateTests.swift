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

    @Test func screensWithoutANotchGetAVirtualNotch() {
        let model = makeModel()
        model.screen = ScreenMetrics(size: CGSize(width: 2560, height: 1440), notch: nil, menuBarHeight: 25)
        #expect(model.engine.isVirtualNotch)
        model.screen = .sample
        #expect(!model.engine.isVirtualNotch)
    }
}
