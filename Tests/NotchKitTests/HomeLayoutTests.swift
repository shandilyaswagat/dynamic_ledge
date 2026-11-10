import Foundation
import Testing
@testable import NotchKit

@Suite("Home layout")
struct HomeLayoutSelectionTests {
    @Test func startsWithEverythingInTheBuiltInOrder() {
        let layout = HomeLayoutSelection.standard
        #expect(layout.visibleItems == HomeLayoutSelection.defaultOrder)
        #expect(layout.entries.count == HomeItem.allCases.count)
    }

    @Test func fillsInMissingItemsAndDropsRepeats() {
        let layout = HomeLayoutSelection(entries: [
            .init(item: .stats),
            .init(item: .stats, isVisible: false),
            .init(item: .calendar, isVisible: false),
        ])
        #expect(layout.entries.count == HomeItem.allCases.count)
        #expect(layout.entries[0].item == .stats && layout.entries[0].isVisible, "the first repeat wins")
        #expect(!layout.isVisible(.calendar))
        #expect(layout.isVisible(.timer), "an item the saved list lacks is shown")
    }

    @Test func movesAndHidesItems() {
        var layout = HomeLayoutSelection.standard
        let movedUp = layout.move(.timer, by: -1)
        #expect(movedUp)
        #expect(layout.entries[1].item == .timer && layout.entries[2].item == .calendar)
        let firstUp = layout.move(.live, by: -1)
        #expect(!firstUp, "the first item can't go up")
        let lastDown = layout.move(.stats, by: 1)
        #expect(!lastDown, "the last item can't go down")
        layout.setVisible(.calendar, false)
        #expect(!layout.visibleItems.contains(.calendar))
        #expect(layout.visibleItems.first == .live)
    }

    @Test func dragsItemsAndKeepsEveryOne() {
        var layout = HomeLayoutSelection.standard
        layout.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(layout.entries.prefix(3).map(\.item) == [.calendar, .timer, .live])
        layout.move(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(layout.entries.count == HomeItem.allCases.count)
        #expect(Set(layout.entries.map(\.item)).count == HomeItem.allCases.count)
    }

    @Test func savesAndIgnoresWhatItDoesNotKnow() throws {
        var layout = HomeLayoutSelection.standard
        layout.setVisible(.timer, false)
        let data = try #require(layout.data)
        #expect(HomeLayoutSelection(data: data) == layout)

        let future = Data(#"{"entries":[{"item":"weather","isVisible":true},{"item":"timer","isVisible":false}]}"#.utf8)
        let loaded = try #require(HomeLayoutSelection(data: future))
        #expect(loaded.entries.count == HomeItem.allCases.count)
        #expect(loaded.entries[0].item == .timer && !loaded.isVisible(.timer))
        #expect(HomeLayoutSelection(data: Data("not json".utf8)) == nil)
    }

    @Test func onlySomeItemsFitTheStandardLayout() {
        #expect(HomeItem.allCases.filter(\.inStandardLayout) == [.live, .calendar, .timer, .shortcuts, .aiUsage, .tiles])
    }

    @Test func theElongatedBuiltInKeepsItsOwnOrder() {
        let layout = HomeLayoutSelection.builtIn(elongated: true)
        #expect(layout.visibleItems == [.live, .mirror, .calendar, .notes, .timer, .todos, .stats, .aiUsage, .tiles])
        #expect(HomeLayoutSelection.builtIn(elongated: false) == .standard)
    }
}

@Suite("Home tiles")
struct HomeTileTests {
    private func website(_ target: String) -> HomeTile {
        HomeTile(title: "a", symbol: "star.fill", kind: .website, target: target)
    }

    @Test func websiteAddressesAreCleanedUp() {
        #expect(website("example.com/docs").webURL?.absoluteString == "https://example.com/docs")
        #expect(website("http://a.b").webURL?.scheme == "http")
        #expect(website("things:///add").webURL?.scheme == "things", "an app's own link scheme works")
        #expect(website("file:///etc/passwd").webURL == nil, "files aren't opened from a website tile")
        #expect(website("not a url").webURL == nil)
        #expect(website("https://").webURL == nil)
    }

    @Test func aTileNeedsANameAndATarget() {
        #expect(!HomeTile(title: " ", symbol: "star.fill", kind: .app, target: "/A.app").isComplete)
        #expect(!HomeTile(title: "A", symbol: "star.fill", kind: .app, target: "  ").isComplete)
        #expect(HomeTile(title: "A", symbol: "star.fill", kind: .app, target: "/A.app").isComplete)
    }

    @Test func featureTilesNeedAFeatureThisVersionHas() {
        let clipboard = HomeTile(title: "Clipboard", symbol: "doc.on.clipboard", kind: .feature, target: "clipboard")
        #expect(clipboard.isComplete)
        #expect(clipboard.featureItem == .clipboard)
        #expect(clipboard.summary == "Clipboard")
        #expect(!HomeTile(title: "Weather", symbol: "cloud", kind: .feature, target: "weather").isComplete, "an unknown feature can't be saved")
        #expect(HomeTile(title: "A", symbol: "star.fill", kind: .app, target: "clipboard").featureItem == nil)
    }

    @Test func savedTilesAreLimitedAndUnique() throws {
        let many = (0..<9).map { HomeTile(title: "t\($0)", symbol: "star.fill", kind: .shortcut, target: "s\($0)") }
        let encodedMany = try #require(HomeTile.encode(many))
        let kept = try #require(HomeTile.decode(encodedMany))
        #expect(kept.count == HomeTile.maximum)
        let encodedTwice = try #require(HomeTile.encode([many[0], many[0]]))
        let twice = try #require(HomeTile.decode(encodedTwice))
        #expect(twice.count == 1)
        #expect(HomeTile.decode(Data("nope".utf8)) == nil)
    }
}

@MainActor
@Suite("Home settings")
struct HomeSettingsTests {
    private func store() -> (SettingsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        return (SettingsStore(defaults: defaults), defaults)
    }

    @Test func homeIsBuiltInUntilTheUserChangesIt() {
        let (settings, _) = store()
        #expect(!settings.homeCustomized)
        #expect(settings.effectiveHomeLayout == .builtIn(elongated: false))
        settings.appearance.nookLayout = .elongated
        #expect(settings.effectiveHomeLayout == .builtIn(elongated: true))
    }

    @Test func savingATileMakesHomeTheUsersOwn() {
        let (settings, _) = store()
        #expect(!settings.saveHomeTile(HomeTile(title: "", symbol: "star.fill", kind: .app, target: "")), "an incomplete tile is refused")
        #expect(settings.saveHomeTile(HomeTile(title: "Docs", symbol: "globe", kind: .website, target: "example.com")))
        #expect(settings.homeCustomized)
        #expect(settings.homeLayout == .builtIn(elongated: false), "it starts from what Home showed")

        var tile = settings.homeTiles[0]
        tile.title = "Docs 2"
        #expect(settings.saveHomeTile(tile))
        #expect(settings.homeTiles.count == 1 && settings.homeTiles[0].title == "Docs 2", "editing replaces the tile")

        for index in 0..<10 {
            settings.saveHomeTile(HomeTile(title: "t\(index)", symbol: "star.fill", kind: .shortcut, target: "s\(index)"))
        }
        #expect(settings.homeTiles.count == HomeTile.maximum)
    }

    @Test func featuresFollowTheirSwitches() {
        let (settings, _) = store()
        #expect(settings.isFeatureEnabled(.clipboard))
        settings.clipboardEnabled = false
        #expect(!settings.isFeatureEnabled(.clipboard))
        settings.timerEnabled = false
        #expect(!settings.isFeatureEnabled(.timer) && !settings.isFeatureEnabled(.stopwatch))
        #expect(settings.isFeatureEnabled(.keepAwake), "Keep Awake is always available")
    }

    @Test func choicesSurviveARestartAndReset() {
        let (settings, defaults) = store()
        settings.saveHomeTile(HomeTile(title: "Docs", symbol: "globe", kind: .website, target: "example.com"))
        settings.updateHomeLayout {
            $0.move(.timer, by: -1)
            $0.setVisible(.calendar, false)
        }
        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.homeCustomized)
        #expect(reopened.homeLayout == settings.homeLayout)
        #expect(reopened.homeTiles == settings.homeTiles)
        #expect(!reopened.homeLayout.isVisible(.calendar))

        settings.resetHome()
        let afterReset = SettingsStore(defaults: defaults)
        #expect(!settings.homeCustomized && settings.homeTiles.isEmpty)
        #expect(!afterReset.homeCustomized && afterReset.homeTiles.isEmpty)
    }
}
