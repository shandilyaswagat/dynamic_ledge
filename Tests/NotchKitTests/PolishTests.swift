import AppKit
import EventKit
import Foundation
import Testing
@testable import NotchKit

@Suite("Calendar polish")
struct CalendarPolishTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    @Test func allDayEventsLeadTheirDayAndNeverRing() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 9))!
        let dayStart = calendar.startOfDay(for: now)
        let allDay = CalendarEvent(id: "a", title: "Holiday", start: dayStart, end: dayStart.addingTimeInterval(86400), isAllDay: true)
        let meeting = CalendarEvent(id: "m", title: "Standup", start: now.addingTimeInterval(1800), end: now.addingTimeInterval(3600))
        #expect(CalendarRules.upcoming(in: [meeting, allDay], at: now, limit: 3).map(\.id) == ["a", "m"])
        #expect(CalendarRules.nextEvent(in: [allDay, meeting], at: now)?.id == "m")
        #expect(CalendarRules.nextReminder(in: [allDay], after: now, reminded: []) == nil)
        #expect(CalendarRules.timeRange(for: allDay, at: now) == "All day")
    }

    @Test func laterDaysSayWhichDay() {
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 20))!
        let tomorrow = CalendarEvent(id: "t", title: "Review", start: now.addingTimeInterval(14 * 3600), end: now.addingTimeInterval(15 * 3600))
        #expect(CalendarRules.dayLabel(for: tomorrow, at: now, calendar: calendar) == "Tomorrow")
        #expect(CalendarRules.relativeLabel(for: tomorrow, at: now, calendar: calendar).hasPrefix("Tomorrow "))
        let today = CalendarEvent(id: "n", title: "Now", start: now.addingTimeInterval(-60), end: now.addingTimeInterval(600))
        #expect(CalendarRules.dayLabel(for: today, at: now, calendar: calendar) == "Today")
    }

    @Test func allowingAccessCountsEvenBeforeMacOSCatchesUp() {
        // Right after the user allows access, macOS can still say "not asked yet".
        #expect(CalendarService.access(for: .notDetermined, grantedThisSession: true) == .granted)
        #expect(CalendarService.access(for: .notDetermined, grantedThisSession: false) == .notAsked)
        #expect(CalendarService.access(for: .fullAccess, grantedThisSession: false) == .granted)
        #expect(CalendarService.access(for: .writeOnly, grantedThisSession: true) == .limited)
        #expect(CalendarService.access(for: .denied, grantedThisSession: true) == .denied)
        #expect(RemindersService.access(for: .notDetermined, grantedThisSession: true) == .granted)
        #expect(RemindersService.access(for: .notDetermined, grantedThisSession: false) == .notAsked)
    }
}

@MainActor
@Suite("Several apps playing")
struct MediaSourceTests {
    private func playing(_ title: String, _ app: String, isPlaying: Bool = true, now: Date) -> NowPlayingInfo {
        NowPlayingInfo(title: title, duration: 300, elapsed: 10, sampledAt: now, playbackRate: isPlaying ? 1 : 0, isPlaying: isPlaying, bundleIdentifier: app)
    }

    @Test func remembersTheAppThatWasPlaying() {
        let service = NowPlayingService()
        let now = Date()
        service.apply(playing("Song", "com.apple.finder", now: now), artworkData: nil, now: now)
        #expect(service.otherSources.isEmpty)
        service.apply(playing("Video", "com.apple.dock", now: now), artworkData: nil, now: now)
        #expect(service.otherSources.map(\.id) == ["com.apple.finder"])
        #expect(service.otherSources.first?.info.title == "Song")
        // Back to the first app: it's current again, and the second is now the other one.
        service.apply(playing("Song", "com.apple.finder", now: now), artworkData: nil, now: now)
        #expect(service.otherSources.map(\.id) == ["com.apple.dock"])
    }

    @Test func forgetsAPausedAppAndFinishedTracks() {
        let service = NowPlayingService()
        let now = Date()
        service.apply(playing("Song", "com.apple.finder", isPlaying: false, now: now), artworkData: nil, now: now)
        service.apply(playing("Video", "com.apple.dock", now: now), artworkData: nil, now: now)
        #expect(service.otherSources.isEmpty, "a paused app isn't still playing")

        service.apply(playing("Song", "com.apple.finder", now: now), artworkData: nil, now: now)
        #expect(service.otherSources.map(\.id) == ["com.apple.dock"])
        service.selectedSourceID = "com.apple.dock"
        service.pruneOtherSources(now: now.addingTimeInterval(400))
        #expect(service.otherSources.isEmpty, "its track has run out")
        #expect(service.selectedSourceID == nil)
    }

    @Test func theMusicViewGrowsForTheSwitcher() {
        let engine = LayoutEngine(screen: .sample, appearance: .standard)
        let plain = engine.layout(for: .expanded(.nowPlaying), home: HomeContent(), hovering: false)
        let switcher = engine.layout(for: .expanded(.nowPlaying), home: HomeContent(hasMediaSwitcher: true), hovering: false)
        #expect(switcher.pill.height - plain.pill.height == IslandMetrics.ContentHeight.mediaSwitcher)
        #expect(switcher.pill.maxY <= engine.windowSize.height)
    }
}

@MainActor
@Suite("Hover to open")
struct HoverOpenTests {
    private func makeModel() -> IslandModel {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        let model = IslandModel(settings: SettingsStore(defaults: defaults), tray: TrayStore(folder: nil), notes: NotesStore(defaults: defaults))
        model.settings.notchOpenMode = .hover
        return model
    }

    @Test(arguments: NotchSize.allCases)
    func theRestingPillOpensHome(size: NotchSize) async throws {
        let model = makeModel()
        model.settings.appearance.size = size
        model.isPreviewing = true
        #expect(model.presentation == .idle)
        let center = CGPoint(x: model.layout.pill.midX, y: model.layout.pill.midY)
        model.pointerMoved(to: center)
        for _ in 0..<60 where model.presentation != .home {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.presentation == .home)
    }

    @Test(arguments: NotchSize.allCases)
    func theNotchOpensHomeFromItsEdge(size: NotchSize) async throws {
        let model = makeModel()
        model.settings.appearance.size = size
        let notch = model.engine.notchInWindow
        // Just past the camera housing, on the peek it swells into.
        model.pointerMoved(to: CGPoint(x: notch.maxX + 6, y: 10))
        for _ in 0..<60 where model.presentation != .home {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.presentation == .home)
    }
}

@Suite("Display choice")
struct DisplayChoiceTests {
    @Test func survivesSavingAndLoading() {
        for choice: DisplayChoice in [.automatic, .main, .followPointer, .all, .specific("37D8832A-2D66-02CA-B9F7-8F30A301B230")] {
            #expect(DisplayChoice(rawValue: choice.rawValue) == choice)
        }
        #expect(DisplayChoice(rawValue: "display:") == nil)
        #expect(DisplayChoice(rawValue: "moon") == nil)
    }
}

@MainActor
@Suite("All displays")
struct AllDisplaysTests {
    private func makeModel() -> IslandModel {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        return IslandModel(settings: SettingsStore(defaults: defaults), tray: TrayStore(folder: nil), notes: NotesStore(defaults: defaults))
    }

    private let external = ScreenMetrics(size: CGSize(width: 2560, height: 1440), notch: nil, menuBarHeight: 25)

    @Test func openedThingsShowOnlyOnTheScreenInUse() {
        let model = makeModel()
        model.useOnly(display: 1, metrics: .sample)
        model.timer.start(duration: 300)
        model.expand(.home)
        #expect(model.presentation(onDisplay: 1) == .home)
        #expect(model.presentation(onDisplay: 2) == .compact(primary: .timer, secondary: nil))
        #expect(model.layout(onDisplay: 2, metrics: external).flare > 0, "no notch: still a notch")
        model.cancelTimer()
    }

    @Test func switchesScreensOnlyWhenNothingIsOpen() {
        let model = makeModel()
        model.useOnly(display: 1, metrics: .sample)
        model.expand(.home)
        #expect(!model.activate(display: 2, metrics: external))
        #expect(model.activeDisplayID == 1)
        model.collapse()
        #expect(model.activate(display: 2, metrics: external))
        #expect(model.activeDisplayID == 2)
        #expect(model.screen == external)
    }
}

@Suite("Stats maths")
struct StatsMathTests {
    @Test func cpuIsTheBusyShareBetweenReadings() {
        let old = StatsMath.CPUTicks(user: 100, system: 50, idle: 850, nice: 0)
        let new = StatsMath.CPUTicks(user: 200, system: 100, idle: 1_100, nice: 0)
        #expect(abs(StatsMath.cpuUsage(from: old, to: new) - 0.375) < 1e-9)
        #expect(StatsMath.cpuUsage(from: new, to: new) == 0, "no time passed")
        #expect(StatsMath.cpuUsage(from: new, to: old) == 0, "counters that went backwards read as idle")
    }

    @Test func networkRatesIgnoreWrappedCounters() {
        #expect(StatsMath.rate(from: 1_000, to: 3_000, seconds: 2) == 1_000)
        #expect(StatsMath.rate(from: 4_000_000_000, to: 10, seconds: 2) == 0)
        #expect(StatsMath.rate(from: 0, to: 10, seconds: 0) == 0)
    }

    @Test func labelsReadNaturally() {
        #expect(StatsMath.percent(0.624) == "62%")
        #expect(StatsMath.percent(1.7) == "100%")
        #expect(StatsMath.rate(12) == "0 KB/s")
        #expect(StatsMath.rate(2_500_000).hasSuffix("MB/s"))
        #expect(StatsMath.level(0.5) == .normal && StatsMath.level(0.8) == .busy && StatsMath.level(0.95) == .high)
        let snapshot = SystemSnapshot(memoryUsed: 8, memoryTotal: 16, diskFree: 25, diskTotal: 100)
        #expect(snapshot.memory == 0.5 && snapshot.disk == 0.75)
    }
}

@MainActor
@Suite("Stats in the notch")
struct StatsModelTests {
    private func makeModel() -> IslandModel {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        let model = IslandModel(settings: SettingsStore(defaults: defaults), tray: TrayStore(folder: nil), notes: NotesStore(defaults: defaults))
        model.screen = .sample
        return model
    }

    @Test func offByDefault() {
        let model = makeModel()
        #expect(!model.settings.statsEnabled)
        #expect(model.presentation == .hidden(peek: false))
    }

    @Test func showsOnlyWhenNothingElseIsOn() {
        let model = makeModel()
        model.settings.statsEnabled = true
        #expect(model.presentation == .compact(primary: .stats, secondary: nil))
        model.startTimer(60)
        #expect(model.presentation == .compact(primary: .timer, secondary: nil), "never shares the notch")
        model.cancelTimer()
        #expect(model.presentation == .compact(primary: .stats, secondary: nil))
    }

    @Test func clickingItOpensTheStatsPanel() {
        let model = makeModel()
        model.settings.statsEnabled = true
        model.tapPill()
        #expect(model.presentation == .nook(.stats))
    }

    @Test func theTileIsASwitch() {
        let model = makeModel()
        #expect(!model.isLive(.stats))
        model.open(.stats)
        #expect(model.settings.statsEnabled && model.isLive(.stats))
        #expect(model.activeActivities == [.stats])
        model.open(.stats)
        #expect(!model.settings.statsEnabled)
        #expect(model.activeActivities.isEmpty)
    }
}

@Suite("Elongated layout")
struct ElongatedLayoutTests {
    private func engine(_ layout: NookLayout, screen: ScreenMetrics = .sample) -> LayoutEngine {
        var appearance = NotchAppearance.standard
        appearance.nookLayout = layout
        return LayoutEngine(screen: screen, appearance: appearance)
    }

    @Test func homeAndItsTabsStretchAcrossTheTop() {
        let standard = engine(.standard), elongated = engine(.elongated)
        for presentation in [IslandPresentation.home, .tray, .clipboard] {
            let wide = elongated.layout(for: presentation, home: HomeContent(), hovering: false)
            #expect(wide.pill.width > standard.layout(for: presentation, home: HomeContent(), hovering: false).pill.width + 400)
            #expect(wide.pill.minX >= IslandMetrics.Nook.elongatedEdge - 1)
            #expect(wide.pill.maxX <= ScreenMetrics.sample.size.width - IslandMetrics.Nook.elongatedEdge + 1)
            #expect(wide.pill.minY == 0)
        }
    }

    @Test func panelsKeepTheirOwnSize() {
        for presentation in [IslandPresentation.nook(.launcher), .nook(.calendar), .nook(.timers), .nook(.stats), .expanded(.nowPlaying)] {
            #expect(engine(.elongated).layout(for: presentation, homeHasMedia: true, hovering: false).pill
                == engine(.standard).layout(for: presentation, homeHasMedia: true, hovering: false).pill)
        }
    }

    @Test func fitsAnExternalScreenToo() {
        let external = ScreenMetrics(size: CGSize(width: 2560, height: 1440), notch: nil, menuBarHeight: 25)
        let elongated = engine(.elongated, screen: external)
        let home = elongated.layout(for: .home, home: HomeContent(), hovering: false)
        #expect(home.pill.width <= IslandMetrics.Nook.elongatedMaxWidth + 2 * IslandMetrics.expandedFlare)
        #expect(abs(home.pill.midX - external.size.width / 2) < 1)
        #expect(home.pill.maxY <= elongated.windowSize.height)
    }

    @MainActor
    @Test func layoutChoicePersists() {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        #expect(store.appearance.nookLayout == .standard)
        store.appearance.nookLayout = .elongated
        #expect(SettingsStore(defaults: defaults).appearance.nookLayout == .elongated)
    }
}

@Suite("Meeting links")
struct MeetingLinkTests {
    @Test func findsTheCallInAnEvent() throws {
        let meet = try #require(MeetingLinks.joinLink(in: [nil, "Room 4", "Join: https://meet.google.com/abc-defg-hij"]))
        #expect(meet.provider == .meet && meet.url.host == "meet.google.com")
        #expect(MeetingLinks.joinLink(in: ["https://us02web.zoom.us/j/123456789?pwd=x"])?.provider == .zoom)
        #expect(MeetingLinks.joinLink(in: ["https://teams.microsoft.com/l/meetup-join/19%3ameeting_x"])?.provider == .teams)
        #expect(MeetingLinks.joinLink(in: ["https://acme.webex.com/meet/pat"])?.provider == .webex)
    }

    @Test func ignoresOrdinaryLinks() {
        #expect(MeetingLinks.joinLink(in: ["https://zoom.us/pricing", "https://example.com", "Lunch at noon"]) == nil)
        #expect(MeetingLinks.joinLink(in: [nil, ""]) == nil)
    }
}

@MainActor
@Suite("To-dos")
struct TodoStoreTests {
    private func makeStore() -> (TodoStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        return (TodoStore(defaults: defaults), defaults)
    }

    @Test func addsTicksAndRemembers() throws {
        let (store, defaults) = makeStore()
        store.add("  Buy milk ")
        store.add("Call Sam")
        store.add("   ")
        #expect(store.items.map(\.title) == ["Call Sam", "Buy milk"], "newest first, blanks ignored")
        let milk = try #require(store.items.last)
        store.toggle(milk.id)
        #expect(store.ordered.last?.title == "Buy milk", "done ones sink to the bottom")
        #expect(store.openCount == 1)
        #expect(TodoStore(defaults: defaults).items == store.items, "saved on this Mac")
        store.clearDone()
        #expect(store.items.map(\.title) == ["Call Sam"])
    }

    @Test func keepsAtMostFifty() {
        let (store, _) = makeStore()
        for index in 0..<60 { store.add("Task \(index)") }
        #expect(store.items.count == TodoStore.capacity)
        #expect(store.items.first?.title == "Task 59")
    }
}

@MainActor
@Suite("Formatted notes")
struct RichNotesTests {
    @Test func keepsFormattingAcrossLaunches() throws {
        let defaults = try #require(UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)"))
        let notes = NotesStore(defaults: defaults)
        let bold = NSAttributedString(string: "Ship it", attributes: [.font: NSFontManager.shared.convert(.systemFont(ofSize: 13), toHaveTrait: .boldFontMask)])
        notes.update(bold)
        notes.save()
        let reloaded = NotesStore(defaults: defaults)
        #expect(reloaded.text == "Ship it")
        let font = try #require(reloaded.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.boldFontMask))
    }

    @Test func plainTextFromAnOlderVersionWins() throws {
        let defaults = try #require(UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)"))
        let notes = NotesStore(defaults: defaults)
        notes.update(NSAttributedString(string: "Old"))
        notes.save()
        defaults.set("Edited elsewhere", forKey: "notes.text")
        #expect(NotesStore(defaults: defaults).attributedText.string == "Edited elsewhere")
    }
}

@Suite("Drop zones")
struct DropSplitTests {
    @Test func trayGetsTheWiderLeftSide() {
        let content = CGRect(x: 100, y: 0, width: 400, height: 100)
        #expect(DropPolicy.destination(at: CGPoint(x: 100 + 400 * 0.55, y: 50), content: content, tray: true, airDrop: true) == .tray)
        #expect(DropPolicy.destination(at: CGPoint(x: 100 + 400 * 0.65, y: 50), content: content, tray: true, airDrop: true) == .airDrop)
        #expect(DropPolicy.destination(at: CGPoint(x: 490, y: 50), content: content, tray: true, airDrop: false) == .tray)
    }
}

@Suite("Grid pages")
struct GridPageTests {
    @Test func fiveToARowTenToAPage() {
        let pages = LauncherBody.pages(LauncherItem.allCases)
        #expect(LauncherBody.columns == 5)
        #expect(pages.count == 2)
        #expect(pages[0].count == 10 && pages[1] == [.stats])
        #expect(LauncherBody.pages(Array(LauncherItem.allCases.prefix(4))).count == 1)
        #expect(LauncherBody.pages([]).count == 1, "an empty grid still has its page")
    }
}

@Suite("Stats readings")
struct StatsReadingTests {
    @Test func memoryColourFollowsPressureNotPercent() {
        #expect(StatsMath.pressure(1) == .normal)
        #expect(StatsMath.pressure(2) == .busy)
        #expect(StatsMath.pressure(4) == .high)
    }

    @Test func onlyRealLinksCountTowardsNetworkSpeed() {
        #expect(StatsMath.countsTraffic(interface: "en0"))
        #expect(StatsMath.countsTraffic(interface: "en7"))
        for tunnel in ["utun3", "bridge100", "lo0", "awdl0", "llw0", "anpi0"] {
            #expect(!StatsMath.countsTraffic(interface: tunnel), "\(tunnel)")
        }
    }
}

@MainActor
@Suite("Stats sampling")
struct StatsSamplingTests {
    @Test func readsOnlyWhileItShows() async throws {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        let model = IslandModel(settings: SettingsStore(defaults: defaults), tray: TrayStore(folder: nil), notes: NotesStore(defaults: defaults))
        model.screen = .sample
        // Changes are picked up on the next turn of the main loop, as in the app.
        func settle(until done: () -> Bool) async throws {
            for _ in 0..<50 where !done() { try await Task.sleep(for: .milliseconds(10)) }
        }
        model.open(.stats)
        #expect(model.stats.isRunning)
        model.startTimer(60)
        try await settle { !model.stats.isRunning }
        #expect(!model.stats.isRunning, "a timer pushed it aside")
        model.cancelTimer()
        try await settle { model.stats.isRunning }
        #expect(model.stats.isRunning)
        model.open(.stats)
        #expect(!model.stats.isRunning)
    }

    @Test func hoveringStatsOpensHome() async throws {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        let model = IslandModel(settings: SettingsStore(defaults: defaults), tray: TrayStore(folder: nil), notes: NotesStore(defaults: defaults))
        model.screen = .sample
        model.settings.statsEnabled = true
        model.settings.notchOpenMode = .hover
        model.settings.hoverDelay = 0.1
        let pill = model.layout.pill
        _ = model.pointerMoved(to: CGPoint(x: pill.midX, y: pill.midY))
        for _ in 0..<60 where model.presentation != .home {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.presentation == .home)
    }
}

@Suite("Hanging up")
struct CallHangupTests {
    @Test func onlyAppsWithADocumentedShortcut() throws {
        let teams = try #require(CallHangup.shortcut(for: "com.microsoft.teams2"))
        #expect(teams.flags.contains(.maskCommand) && teams.flags.contains(.maskShift))
        #expect(CallHangup.shortcut(for: "com.microsoft.teams") == teams)
        #expect(try #require(CallHangup.shortcut(for: "us.zoom.xos")).asksToConfirm)
        #expect(CallHangup.shortcut(for: "Cisco-Systems.Spark") != nil)
        for app in ["com.apple.FaceTime", "com.google.Chrome", "com.apple.Safari", "com.tinyspeck.slackmacgap", nil] as [String?] {
            #expect(CallHangup.shortcut(for: app) == nil, "\(app ?? "nil") gets no hang-up button")
        }
    }
}
