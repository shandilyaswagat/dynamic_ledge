import AppKit
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
        let notch = try #require(model.engine.notchInWindow)
        // Just past the camera housing, on the peek it swells into.
        model.pointerMoved(to: CGPoint(x: notch.maxX + 6, y: 10))
        for _ in 0..<60 where model.presentation != .home {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.presentation == .home)
    }
}
