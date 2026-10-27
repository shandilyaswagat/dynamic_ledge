import AppKit
import Foundation
import Testing
@testable import NotchKit

@Suite("Stopwatch")
struct StopwatchTests {
    @Test func countsOnlyWhileRunning() {
        let start = Date(timeIntervalSince1970: 1000)
        var watch = Stopwatch()
        watch.start(now: start)
        #expect(watch.elapsed(at: start.addingTimeInterval(10)) == 10)
        watch.pause(now: start.addingTimeInterval(10))
        #expect(watch.elapsed(at: start.addingTimeInterval(60)) == 10)
        watch.start(now: start.addingTimeInterval(60))
        #expect(watch.elapsed(at: start.addingTimeInterval(65)) == 15)
        #expect(watch.isRunning)
    }

    @Test func formatsTenths() {
        #expect(StopwatchFormat.text(7.46) == "0:07.4")
        #expect(StopwatchFormat.text(3723) == "1:02:03")
    }
}

@Suite("Calendar panel")
struct CalendarPanelTests {
    @Test func monthStartsOnTheRightWeekday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        // 1 October 2026 is a Thursday.
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
        let month = MonthLayout(containing: date, calendar: calendar)
        #expect(month.cells.prefix(4).allSatisfy { $0 == nil })
        #expect(month.cells[4] == 1)
        #expect(month.cells.compactMap { $0 }.count == 31)
        #expect(month.today == 22)
        #expect(month.weekdaySymbols.count == 7)
    }

    @Test func upcomingSkipsWhatsOver() {
        let now = Date(timeIntervalSince1970: 100_000)
        let events = (0..<5).map { index in
            CalendarEvent(id: "\(index)", title: "E\(index)", start: now.addingTimeInterval(Double(index - 1) * 3600), end: now.addingTimeInterval(Double(index - 1) * 3600 + 1800))
        }
        let upcoming = CalendarRules.upcoming(in: events, at: now, limit: 3)
        #expect(upcoming.map(\.id) == ["1", "2", "3"])
    }
}

@Suite("Downloads")
struct DownloadRulesTests {
    @Test func skipsPartialAndHiddenFiles() {
        #expect(DownloadRules.isFinishedName("Report.pdf"))
        #expect(!DownloadRules.isFinishedName("Report.pdf.crdownload"))
        #expect(!DownloadRules.isFinishedName("Movie.mp4.download"))
        #expect(!DownloadRules.isFinishedName(".DS_Store"))
    }
}

@MainActor
@Suite("Timer panel and gestures")
struct TimerPanelModelTests {
    private func makeModel() -> IslandModel {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        return IslandModel(
            settings: SettingsStore(defaults: defaults),
            tray: TrayStore(folder: nil),
            clipboard: ClipboardMonitor(pasteboard: NSPasteboard(name: NSPasteboard.Name("NotchTests-\(UUID().uuidString)"))),
            notes: NotesStore(defaults: defaults)
        )
    }

    @Test func panelsOpenInTheNook() {
        let model = makeModel()
        model.showTab(.timers)
        #expect(model.presentation == .nook(.timers))
        #expect(model.presentation.homeTab?.isPanel == true)
        model.showTab(.home)
        #expect(model.presentation == .home)
    }

    @Test func startsWhatThePanelShows() {
        let model = makeModel()
        model.timerPanelMode = .timer
        model.timerPanelMinutes = 7
        model.startFromPanel()
        #expect(model.timer.timer?.duration == TimeInterval(7 * 60))
        model.cancelTimer()

        model.timerPanelMode = .focus
        model.focusPanelMinutes = 40
        model.startFromPanel()
        #expect(model.timer.timer?.mode == .focus)
        #expect(model.timer.timer?.duration == TimeInterval(40 * 60))
        model.cancelTimer()

        model.timerPanelMode = .stopwatch
        model.startFromPanel()
        #expect(model.activeActivities.contains(.stopwatch))
        #expect(model.presentation == .compact(primary: .stopwatch, secondary: nil))
        model.resetStopwatch()
        #expect(!model.activeActivities.contains(.stopwatch))
    }

    @Test func pullingOpensAndCloses() {
        let model = makeModel()
        model.pull(open: true)
        #expect(model.presentation == .home)
        model.pull(open: false)
        #expect(model.presentation == .hidden(peek: false))
        model.stopwatch.start()
        model.pull(open: true)
        #expect(model.presentation == .expanded(.stopwatch))
        model.resetStopwatch()
    }

    @Test func swipingSwapsActivitiesWhenMusicIsntInFront() {
        let model = makeModel()
        model.timer.start(duration: 300)
        model.stopwatch.start()
        #expect(model.presentation == .compact(primary: .timer, secondary: .stopwatch))
        model.swipe(forward: true)
        #expect(model.presentation == .compact(primary: .stopwatch, secondary: .timer))
        model.cancelTimer()
        model.resetStopwatch()
    }
}
