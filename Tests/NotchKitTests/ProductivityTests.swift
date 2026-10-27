import AppKit
import Foundation
import Testing
@testable import NotchKit

@Suite("Clipboard history")
struct ClipboardHistoryTests {
    @Test func newestFirstWithoutRepeats() {
        var history = ClipboardHistory()
        history.add("one")
        history.add("two")
        history.add("one")
        #expect(history.entries.map(\.text) == ["one", "two"])
    }

    @Test func skipsBlankText() {
        var history = ClipboardHistory()
        let added = history.add("  \n\t")
        #expect(!added)
        #expect(history.entries.isEmpty)
    }

    @Test func keepsOnlyTheNewest() {
        var history = ClipboardHistory()
        for index in 0..<(ClipboardHistory.capacity + 5) {
            history.add("item \(index)")
        }
        #expect(history.entries.count == ClipboardHistory.capacity)
        #expect(history.entries.first?.text == "item \(ClipboardHistory.capacity + 4)")
    }

    @Test func cutsVeryLongCopies() {
        var history = ClipboardHistory()
        history.add(String(repeating: "a", count: ClipboardHistory.maximumLength + 100))
        #expect(history.entries.first?.text.count == ClipboardHistory.maximumLength)
    }

    @Test func removes() throws {
        var history = ClipboardHistory()
        history.add("keep")
        history.add("drop")
        let id = try #require(history.entries.first?.id)
        history.remove(id)
        #expect(history.entries.map(\.text) == ["keep"])
        history.removeAll()
        #expect(history.entries.isEmpty)
    }

    @Test func previewIsOneLine() {
        #expect(ClipboardHistory.preview("a\n\n  b\tc") == "a b c")
        #expect(ClipboardHistory.preview("abcdef", limit: 3) == "abc…")
    }

    @Test func passwordsAreNeverRecorded() {
        #expect(!ClipboardRules.shouldRecord(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        #expect(!ClipboardRules.shouldRecord(types: ["org.nspasteboard.TransientType"]))
        #expect(ClipboardRules.shouldRecord(types: ["public.utf8-plain-text"]))
    }
}

@MainActor
@Suite("Clipboard monitor")
struct ClipboardMonitorTests {
    private func pasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("NotchTests-\(UUID().uuidString)"))
    }

    @Test func recordsCopiedText() {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board)
        monitor.start()
        defer { monitor.stop() }
        board.clearContents()
        board.setString("hello", forType: .string)
        monitor.check()
        #expect(monitor.history.entries.map(\.text) == ["hello"])
    }

    @Test func skipsConcealedCopies() {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board)
        monitor.start()
        defer { monitor.stop() }
        board.clearContents()
        board.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        board.setString("secret", forType: .string)
        monitor.check()
        #expect(monitor.history.entries.isEmpty)
    }

    @Test func copyingBackMovesToFrontWithoutDuplicating() throws {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board)
        monitor.start()
        defer { monitor.stop() }
        for text in ["first", "second"] {
            board.clearContents()
            board.setString(text, forType: .string)
            monitor.check()
        }
        let first = try #require(monitor.history.entries.last)
        monitor.copy(first)
        monitor.check()
        #expect(monitor.history.entries.map(\.text) == ["first", "second"])
        #expect(board.string(forType: .string) == "first")
    }

    @Test func stoppingForgetsHistory() {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        let monitor = ClipboardMonitor(pasteboard: board)
        monitor.start()
        board.clearContents()
        board.setString("x", forType: .string)
        monitor.check()
        monitor.stop()
        #expect(monitor.history.entries.isEmpty)
        #expect(!monitor.isRunning)
    }
}

@MainActor
@Suite("Notes")
struct NotesTests {
    @Test func survivesRelaunch() throws {
        let defaults = try #require(UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)"))
        let notes = NotesStore(defaults: defaults)
        notes.setText("Buy milk")
        notes.save()
        #expect(NotesStore(defaults: defaults).text == "Buy milk")
        notes.clear()
        #expect(NotesStore(defaults: defaults).isEmpty)
    }
}

@Suite("Focus sessions")
struct FocusModeTests {
    @Test func focusAndBreakAlternate() {
        #expect(TimerMode.focus.next == .rest)
        #expect(TimerMode.rest.next == .focus)
        #expect(TimerMode.plain.next == nil)
    }

    @Test func timerKeepsItsMode() {
        let timer = CountdownTimer(duration: 1500, now: Date(), mode: .focus)
        #expect(timer.mode == .focus)
        #expect(CountdownTimer(duration: 60, now: Date()).mode == .plain)
    }
}

@MainActor
@Suite("Productivity in the model")
struct ProductivityModelTests {
    private func makeModel() -> IslandModel {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        return IslandModel(
            settings: SettingsStore(defaults: defaults),
            tray: TrayStore(folder: nil),
            clipboard: ClipboardMonitor(pasteboard: NSPasteboard(name: NSPasteboard.Name("NotchTests-\(UUID().uuidString)"))),
            notes: NotesStore(defaults: defaults)
        )
    }

    @Test func tabsOpen() {
        let model = makeModel()
        model.showTab(.clipboard)
        #expect(model.presentation == .clipboard)
        model.showTab(.notes)
        #expect(model.presentation == .notes)
        #expect(model.presentation.homeTab == .notes)
        #expect(model.presentation.isExpandedFamily)
    }

    @Test func notesStayOpenWhenThePointerLeaves() async throws {
        let model = makeModel()
        model.showTab(.notes)
        let inside = CGPoint(x: model.layout.pill.midX, y: model.layout.pill.midY)
        model.pointerMoved(to: inside)
        model.pointerMoved(to: nil)
        try await Task.sleep(for: .milliseconds(1100))
        #expect(model.presentation == .notes)
        model.outsideClick()
        #expect(model.presentation == .hidden(peek: false))
    }

    @Test func focusSessionUsesSettings() {
        let model = makeModel()
        model.settings.focusMinutes = 45
        model.startSession(.focus)
        #expect(model.timer.timer?.mode == .focus)
        #expect(model.timer.timer?.duration == TimeInterval(45 * 60))
        model.startSession(.rest)
        #expect(model.timer.timer?.mode == .rest)
        #expect(model.timer.timer?.duration == TimeInterval(model.settings.breakMinutes * 60))
        // Sessions don't replace the plain timer that "Repeat" restarts.
        #expect(model.timer.lastDuration == nil)
        model.cancelTimer()
    }

    @Test func onlyThreeTabsSitInTheBar() {
        #expect(HomeTab.allCases.filter(\.isTab) == [.home, .tray, .clipboard])
        #expect(HomeTab.allCases.filter(\.isPanel) == [.notes, .mirror, .timers, .calendar, .reminders, .stats])
    }

    @Test func nookTabsShareOneSize() {
        let engine = LayoutEngine(screen: .sample, appearance: .standard)
        let sizes = [IslandPresentation.home, .clipboard, .notes].map { engine.layout(for: $0, home: HomeContent(), hovering: false).pill.size }
        #expect(Set(sizes.map { "\($0)" }).count == 1)
    }
}

@Suite("Greeting")
struct GreetingTests {
    @Test func usesTheFirstName() {
        #expect(Greeting.firstName(fromFullName: "Swagat Shandilya") == "Swagat")
        #expect(Greeting.firstName(fromFullName: "  Ana ") == "Ana")
        #expect(Greeting.text(fullName: "Swagat Shandilya") == "Hi Swagat")
    }

    @Test func fallsBackWithoutAName() {
        #expect(Greeting.firstName(fromFullName: "   ") == nil)
        #expect(Greeting.text(fullName: "") == "Hi there")
    }
}
