import AppKit
import Foundation
import Testing
@testable import NotchKit

private func isolatedDefaults() -> UserDefaults {
    let name = "NotchTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Suite("Pinned clips and search")
struct ClipboardPinTests {
    @Test func pinnedClipsStayOnTopAndSurviveClearing() throws {
        var history = ClipboardHistory()
        history.add("first")
        history.add("second")
        let first = try #require(history.entries.first { $0.text == "first" })
        let pinned = history.togglePin(first.id)
        #expect(pinned)
        history.add("third")
        #expect(history.entries.map(\.text) == ["first", "third", "second"])
        // Copying a pinned clip again doesn't move it or repeat it.
        history.add("first")
        #expect(history.entries.map(\.text) == ["first", "third", "second"])
        history.removeAll()
        #expect(history.entries.map(\.text) == ["first"])
    }

    @Test func pinnedClipsDontCountTowardsTheHistory() throws {
        var history = ClipboardHistory()
        history.add("kept")
        try history.togglePin(#require(history.entries.first?.id))
        for index in 0..<(ClipboardHistory.capacity + 3) { history.add("item \(index)") }
        #expect(history.entries.first?.text == "kept")
        #expect(history.entries.count == ClipboardHistory.capacity + 1)
    }

    @Test func pinsAreLimited() {
        var history = ClipboardHistory()
        for index in 0..<(ClipboardHistory.pinnedCapacity + 1) { history.add("pin \(index)") }
        for entry in history.entries { history.togglePin(entry.id) }
        #expect(history.pinnedCount == ClipboardHistory.pinnedCapacity)
        #expect(!history.canPin)
    }

    @Test func searchMatchesEveryWordIgnoringCase() {
        var history = ClipboardHistory()
        history.add("Meeting link for Friday", appName: "Mail")
        history.add("git push origin main", appName: "Terminal")
        #expect(history.matching("FRIDAY meeting").map(\.text) == ["Meeting link for Friday"])
        #expect(history.matching("terminal").map(\.text) == ["git push origin main"])
        #expect(history.matching("  ").count == 2)
        #expect(history.matching("nothing").isEmpty)
    }

    @MainActor @Test func onlyPinnedClipsAreSaved() throws {
        let defaults = isolatedDefaults()
        let pasteboard = NSPasteboard.withUniqueName()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, defaults: defaults)
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)
        monitor.check()
        pasteboard.clearContents()
        pasteboard.setString("forget me", forType: .string)
        monitor.check()
        try monitor.togglePin(#require(monitor.history.entries.first { $0.text == "keep me" }?.id))
        let reopened = ClipboardMonitor(pasteboard: pasteboard, defaults: defaults)
        #expect(reopened.history.entries.map(\.text) == ["keep me"])
        #expect(reopened.history.entries.first?.isPinned == true)
    }
}

@MainActor
@Suite("Pinned tray items")
struct TrayPinTests {
    @Test func pinnedFilesComeBackAfterARestart() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pinned = folder.appendingPathComponent("pinned.txt")
        let loose = folder.appendingPathComponent("loose.txt")
        try Data().write(to: pinned)
        try Data().write(to: loose)
        let defaults = isolatedDefaults()

        let tray = TrayStore(folder: folder, defaults: defaults)
        tray.add([pinned, loose])
        try tray.togglePin(#require(tray.items.first { $0.name == "pinned.txt" }?.id))
        #expect(tray.ordered.map(\.name) == ["pinned.txt", "loose.txt"])
        tray.removeAll()
        #expect(tray.items.map(\.name) == ["pinned.txt"])
        tray.endSession()

        // A pinned file that's renamed is still found.
        let renamed = folder.appendingPathComponent("renamed.txt")
        try FileManager.default.moveItem(at: pinned, to: renamed)
        let reopened = TrayStore(folder: folder, defaults: defaults)
        #expect(reopened.items.map(\.name) == ["renamed.txt"])
        #expect(reopened.items.first?.isPinned == true)
    }

    @Test func aPinnedFileThatsGoneIsDropped() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NotchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("gone.txt")
        try Data().write(to: file)
        let defaults = isolatedDefaults()
        let tray = TrayStore(folder: folder, defaults: defaults)
        tray.add([file])
        try tray.togglePin(#require(tray.items.first?.id))
        try FileManager.default.removeItem(at: file)
        #expect(TrayStore(folder: folder, defaults: defaults).items.isEmpty)
    }
}

@Suite("Lyrics")
struct LyricsTests {
    @Test func parsesTimedLines() throws {
        let lyrics = try #require(SyncedLyrics(lrc: """
        [ar:Someone]
        [ti:Song]
        [00:01.50] First line
        [00:04.00][00:20.25] Chorus
        [00:08.10]
        [00:10.00] Second line
        """))
        #expect(lyrics.lines.map(\.text) == ["First line", "Chorus", "", "Second line", "Chorus"])
        #expect(lyrics.lines.map(\.time) == [1.5, 4, 8.1, 10, 20.25])
    }

    @Test func findsTheLineBeingSung() throws {
        let lyrics = try #require(SyncedLyrics(lrc: "[00:01.00] a\n[00:05.00] b\n[00:09.00] c"))
        #expect(lyrics.index(at: 0.5) == nil)
        #expect(lyrics.index(at: 1) == 0)
        #expect(lyrics.index(at: 7) == 1)
        #expect(lyrics.index(at: 300) == 2)
    }

    @Test func plainLyricsArentTimed() {
        #expect(SyncedLyrics(lrc: "Just words\nwith no times") == nil)
        #expect(SyncedLyrics(lrc: "[ar:Someone]\n[00:01.00]") == nil)
    }

    @Test func aRecordOfADifferentLengthIsntUsed() throws {
        let key = try #require(LyricsLookup.Key(NowPlayingInfo(title: "Song", artist: "Band", duration: 200)))
        let close = LyricsLookup.Record(duration: 201, instrumental: false, syncedLyrics: "[00:01.00] hi")
        let far = LyricsLookup.Record(duration: 260, instrumental: false, syncedLyrics: "[00:01.00] hi")
        let instrumental = LyricsLookup.Record(duration: 200, instrumental: true, syncedLyrics: nil)
        #expect(LyricsLookup.lyrics(from: close, for: key) != nil)
        #expect(LyricsLookup.lyrics(from: far, for: key) == nil)
        #expect(LyricsLookup.lyrics(from: instrumental, for: key) == nil)
    }

    @Test func noLookupWithoutAnArtist() {
        #expect(LyricsLookup.Key(NowPlayingInfo(title: "Some video")) == nil)
    }

    @Test func requestsAskForTheExactSong() throws {
        let key = try #require(LyricsLookup.Key(NowPlayingInfo(title: "Hey Jude", artist: "The Beatles", album: "1", duration: 431.2)))
        let url = try #require(LyricsLookup.getURL(for: key)).absoluteString
        #expect(url.hasPrefix("https://lrclib.net/api/get?"))
        #expect(url.contains("track_name=Hey%20Jude"))
        #expect(url.contains("duration=431"))
    }
}
