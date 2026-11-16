import Foundation
import Testing
@testable import NotchKit

@Suite("Home grid")
struct HomeGridTests {
    private func place(_ tiles: [HomeTile]) -> [HomeGridLayout.Placement] {
        HomeGridLayout.place(tiles, columns: IslandMetrics.Nook.homeColumns, rowsPerPage: IslandMetrics.Nook.homeRows)
    }

    private func spot(_ item: HomeTileItem, in placements: [HomeGridLayout.Placement]) -> [Int]? {
        placements.first { $0.tile.item == item }.map { [$0.page, $0.column, $0.row] }
    }

    @Test func defaultTilesMatchTheWindowsHome() {
        let placements = place(HomeGrid.defaultTiles)
        #expect(HomeGridLayout.pageCount(placements) == 1, "everything fits on one page")
        #expect(spot(.stats, in: placements) == [0, 0, 0], "Stats, two by two, on the left")
        #expect(spot(.calendar, in: placements) == [0, 2, 0])
        #expect(spot(.reminders, in: placements) == [0, 4, 0])
        #expect(spot(.keepAwake, in: placements) == [0, 2, 1], "small tiles fill the row under the wide ones")
        #expect(spot(.aiUsage, in: placements) == [0, 3, 1])
        #expect(spot(.timer, in: placements) == [0, 4, 1])
        #expect(spot(.stopwatch, in: placements) == [0, 5, 1])
    }

    @Test func aSmallTileFillsAGapLeftBesideABigOne() {
        let placements = place([HomeTile(.calendar, .wide), HomeTile(.stats, .large), HomeTile(.timer, .wide), HomeTile(.keepAwake)])
        #expect(spot(.stats, in: placements) == [0, 2, 0])
        #expect(spot(.timer, in: placements) == [0, 4, 0])
        #expect(spot(.keepAwake, in: placements) == [0, 0, 1], "first free cell, under Calendar")
    }

    @Test func moreTilesMakeMorePagesAndNeverSplitATile() {
        let tiles = HomeTileItem.allCases.map { HomeTile($0, .large) }
        let placements = place(tiles)
        #expect(HomeGridLayout.pageCount(placements) == 4, "three large tiles a page")
        for placement in placements {
            #expect(placement.row + placement.tile.size.rows <= IslandMetrics.Nook.homeRows)
            #expect(placement.column + placement.tile.size.columns <= IslandMetrics.Nook.homeColumns)
        }
        #expect(HomeGridLayout.pageCount(place([])) == 1, "an empty Home keeps its space")
    }

    @Test func sizesStepAndFitTheDraggedSpan() {
        #expect(HomeTileSize.small.next == .wide)
        #expect(HomeTileSize.wide.next == .large)
        #expect(HomeTileSize.large.next == .small)
        #expect(HomeTileSize.fitting(columns: 1, rows: 1) == .small)
        #expect(HomeTileSize.fitting(columns: 0, rows: 3) == .small, "taller alone isn't a size")
        #expect(HomeTileSize.fitting(columns: 3, rows: 1) == .wide)
        #expect(HomeTileSize.fitting(columns: 2, rows: 2) == .large)
    }

    @Test func savedValuesSurviveAndBadOnesAreDropped() {
        let grid = HomeGrid(rawValues: ["stats:large", "calendar:wide", "nowPlaying:small", "bogus", "stats:small", "timer", "shortcuts:huge"])
        #expect(grid.tiles == [HomeTile(.stats, .large), HomeTile(.calendar, .wide), HomeTile(.timer), HomeTile(.shortcuts)])
        #expect(HomeGrid(rawValues: grid.rawValues) == grid)
    }

    @Test func addRemoveResizeAndMove() {
        var grid = HomeGrid(tiles: [HomeTile(.stats, .large), HomeTile(.timer), HomeTile(.keepAwake)])
        let added = grid.add(.mirror)
        let addedAgain = grid.add(.mirror)
        #expect(added)
        #expect(!addedAgain, "once")
        #expect(grid.tiles.last == HomeTile(.mirror))
        grid.resize(.timer, to: .wide)
        #expect(grid.size(of: .timer) == .wide)
        grid.move(.mirror, to: .stats)
        #expect(grid.tiles.map(\.item) == [.mirror, .stats, .timer, .keepAwake])
        grid.move(.mirror, to: .keepAwake)
        #expect(grid.tiles.map(\.item) == [.stats, .timer, .keepAwake, .mirror])
        let removed = grid.remove(.stats)
        let removedAgain = grid.remove(.stats)
        #expect(removed)
        #expect(!grid.contains(.stats))
        #expect(!removedAgain)
    }
}

@MainActor
@Suite("Home grid in the notch")
struct HomeGridModelTests {
    private func makeModel() -> IslandModel {
        let defaults = UserDefaults(suiteName: "HomeGridModelTests.\(UUID().uuidString)")!
        let model = IslandModel(settings: SettingsStore(defaults: defaults), tray: TrayStore(folder: nil))
        model.screen = .sample
        return model
    }

    @Test func tilesAreSavedAndHiddenWhileTheirFeatureIsOff() {
        let defaults = UserDefaults(suiteName: "HomeGridSaved.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.homeTiles == HomeGrid.defaultTiles)
        settings.homeTiles = [HomeTile(.mirror, .wide), HomeTile(.mirror), HomeTile(.timer)]
        #expect(settings.homeTiles == [HomeTile(.mirror, .wide), HomeTile(.timer)], "repeats are dropped")
        #expect(SettingsStore(defaults: defaults).homeTiles == settings.homeTiles, "kept across launches")

        let model = makeModel()
        model.settings.aiUsageEnabled = false
        #expect(!model.homeTiles.map(\.item).contains(.aiUsage), "off in Settings, so not on Home")
        #expect(!model.addableHomeItems.contains(.aiUsage))
        model.settings.aiUsageEnabled = true
        #expect(model.homeTiles.map(\.item).contains(.aiUsage), "back when it's on again")
        model.settings.shortcutsEnabled = true
        #expect(model.addableHomeItems.contains(.shortcuts))
        #expect(!model.addableHomeItems.contains(.stats), "already on Home")
    }

    @Test func editingStartsByHoldingAndEndsWhenAnythingElseOpens() {
        let model = makeModel()
        model.showTab(.home)
        model.startEditingHome()
        #expect(model.isEditingHome)
        #expect(model.homeContent.isEditingHome)
        model.showTab(.tray)
        #expect(!model.isEditingHome)
        model.showTab(.home)
        model.startEditingHome()
        model.collapse()
        #expect(!model.isEditingHome)
        model.showTab(.home)
        model.startEditingHome()
        model.expand(.activity(.timer))
        #expect(!model.isEditingHome)
    }

    @Test func editingChangesTheSavedTilesAndResetBringsBackTheDefault() {
        let model = makeModel()
        model.removeHomeTile(.calendar)
        model.addHomeTile(.mirror)
        model.resizeHomeTile(.mirror, to: .large)
        model.moveHomeTile(.mirror, to: .stats)
        #expect(model.settings.homeTiles.first == HomeTile(.mirror, .large))
        #expect(!model.settings.homeTiles.map(\.item).contains(.calendar))
        model.resetHomeTiles()
        #expect(model.settings.homeTiles == HomeGrid.defaultTiles)
    }

    @Test func homeStatsTileReadsWhileHomeIsOpenEvenWithTheReadoutOff() {
        let model = makeModel()
        model.settings.statsEnabled = false
        model.showTab(.home)
        #expect(model.stats.isRunning, "the large Stats tile shows readings")
        model.collapse()
        #expect(!model.stats.isRunning, "nothing reads once Home closes")
        model.resizeHomeTile(.stats, to: .small)
        model.showTab(.home)
        #expect(!model.stats.isRunning, "a small Stats tile is just the switch")
    }

    @Test func homeGrowsForEditingAndWidensForMusic() {
        let engine = LayoutEngine(screen: .sample, appearance: .standard)
        let plain = engine.layout(for: .home, home: HomeContent(), hovering: false)
        let editing = engine.layout(for: .home, home: HomeContent(isEditingHome: true), hovering: false)
        let music = engine.layout(for: .home, home: HomeContent(hasLiveTile: true), hovering: false)
        #expect(editing.pill.height == plain.pill.height + IslandMetrics.Nook.homeEditExtra, "room for Add controls")
        #expect(editing.pill.width == plain.pill.width)
        #expect(music.pill.width == plain.pill.width + IslandMetrics.Nook.homeLiveWidth + IslandMetrics.Nook.homeGap)
        #expect(music.pill.height == plain.pill.height)
        #expect(engine.windowSize.height >= editing.pill.height, "the window fits editing")
        #expect(engine.windowSize.width >= music.pill.width)

        var elongated = NotchAppearance.standard
        elongated.nookLayout = .elongated
        let wide = LayoutEngine(screen: .sample, appearance: elongated)
        #expect(wide.layout(for: .home, home: HomeContent(hasLiveTile: true, isEditingHome: true), hovering: false).pill.height
                == wide.layout(for: .tray, home: HomeContent(), hovering: false).pill.height, "the elongated layout is unchanged")
    }

    @Test func musicShowsBesideTheGrid() {
        let model = makeModel()
        #expect(model.homeLiveItems.isEmpty)
        #expect(!model.homeContent.hasLiveTile)
        model.nowPlaying.apply(NowPlayingInfo(title: "Song", duration: 200, isPlaying: true), artworkData: nil)
        #expect(model.homeLiveItems == [.music])
        #expect(model.homeContent.hasLiveTile)
        model.startTimer(60)
        #expect(model.homeLiveItems == [.music], "the Timer tile already shows it running")
        model.removeHomeTile(.timer)
        #expect(model.homeLiveItems == [.music, .timer])
    }
}

@Suite("Stats panel readings")
struct StatsPanelTests {
    @Test func cpuHistoryKeepsAMinute() {
        #expect(Double(StatsService.cpuHistoryLimit) * StatsService.interval == 60)
    }

    @Test func batteryEstimateIsOptional() {
        let plain = PowerSnapshot(hasBattery: true, level: 120, isOnAC: false, isCharging: false, isLowPowerMode: false)
        #expect(plain.estimatedMinutes == nil, "no estimate unless macOS gives one")
        #expect(plain.level == 100)
        let charging = PowerSnapshot(hasBattery: true, level: 40, isOnAC: true, isCharging: true, isLowPowerMode: false, estimatedMinutes: 55)
        #expect(charging.estimatedMinutes == 55)
    }
}
