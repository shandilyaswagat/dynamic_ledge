import Foundation
import Testing
@testable import NotchKit

@Suite("Now Playing app filter")
struct MediaAppFilterTests {
    @Test func allAppsAllowsEverything() {
        #expect(MediaAppFilter.all.allows("com.google.Chrome"))
        #expect(MediaAppFilter.all.allows(nil))
    }

    @Test func chosenAppsAllowsOnlyThose() {
        let filter = MediaAppFilter(mode: .chosen, allowed: ["com.spotify.client"])
        #expect(filter.allows("com.spotify.client"))
        #expect(!filter.allows("com.google.Chrome"))
        #expect(!filter.allows(nil), "an unknown app can't be one the user chose")
        #expect(!MediaAppFilter(mode: .chosen, allowed: []).allows("com.spotify.client"))
    }

    @Test func recentAppsKeepOrderAndLimit() {
        var recent = RecentMediaApps(["a", "a", "", "b"])
        #expect(recent.identifiers == ["a", "b"])
        let changedForB = recent.note("b")
        #expect(!changedForB, "already listed, so nothing to save")
        #expect(recent.identifiers == ["a", "b"])
        let changedForC = recent.note("c")
        #expect(changedForC)
        #expect(recent.identifiers == ["c", "a", "b"])
        for index in 0..<20 { recent.note("app\(index)") }
        #expect(recent.identifiers.count == RecentMediaApps.limit)
        #expect(recent.identifiers.first == "app19")
        recent.remove("app19")
        #expect(!recent.identifiers.contains("app19"))
    }
}

@MainActor
@Suite("Now Playing from chosen apps")
struct NowPlayingAppChoiceTests {
    private func playing(_ title: String, _ app: String?, isPlaying: Bool = true, now: Date = Date()) -> NowPlayingInfo {
        NowPlayingInfo(title: title, duration: 300, elapsed: 10, sampledAt: now, playbackRate: isPlaying ? 1 : 0, isPlaying: isPlaying, bundleIdentifier: app)
    }

    @Test func hidesAppsThatWerentChosen() {
        let service = NowPlayingService()
        var seen: [String] = []
        service.onAppSeen = { seen.append($0) }
        service.appFilter = MediaAppFilter(mode: .chosen, allowed: ["com.apple.finder"])

        service.apply(playing("Video", "com.apple.dock"), artworkData: nil)
        #expect(service.info == nil)
        #expect(!service.isActivityVisible)
        #expect(seen == ["com.apple.dock"], "hidden apps are still offered in Settings")

        service.apply(playing("Song", "com.apple.finder"), artworkData: nil)
        #expect(service.info?.title == "Song")
        #expect(service.isActivityVisible)
    }

    @Test func aHiddenAppTakingOverClearsTheNotch() {
        let service = NowPlayingService()
        service.appFilter = MediaAppFilter(mode: .chosen, allowed: ["com.apple.finder"])
        service.apply(playing("Song", "com.apple.finder"), artworkData: nil)
        service.apply(playing("Video", "com.apple.dock"), artworkData: nil)
        #expect(service.info == nil)
        #expect(!service.isLingering, "a hidden app doesn't leave a paused song behind")
        #expect(service.currentSourceID == nil)
    }

    @Test func unknownAppsAreHiddenWhenChoosing() {
        let service = NowPlayingService()
        service.appFilter = MediaAppFilter(mode: .chosen, allowed: ["com.apple.finder"])
        service.apply(playing("Mystery", nil), artworkData: nil)
        #expect(service.info == nil)
    }

    @Test func changingTheChoiceUpdatesWhatShows() {
        let service = NowPlayingService()
        let now = Date()
        service.apply(playing("Song", "com.apple.finder", now: now), artworkData: nil, now: now)
        service.apply(playing("Video", "com.apple.dock", now: now), artworkData: nil, now: now)
        #expect(service.otherSources.map(\.id) == ["com.apple.finder"])
        service.selectedSourceID = "com.apple.finder"

        // Only the Dock now: its video stays, and Finder leaves the switcher.
        service.appFilter = MediaAppFilter(mode: .chosen, allowed: ["com.apple.dock"])
        #expect(service.info?.title == "Video")
        #expect(service.otherSources.isEmpty)
        #expect(service.selectedSourceID == nil)

        service.appFilter = MediaAppFilter(mode: .chosen, allowed: ["com.apple.finder"])
        #expect(service.info == nil)

        service.appFilter = .all
        service.apply(playing("Video", "com.apple.dock", now: now), artworkData: nil, now: now)
        #expect(service.info?.title == "Video")
    }
}

@MainActor
@Suite("Now Playing app settings")
struct NowPlayingAppSettingsTests {
    private func store(_ defaults: UserDefaults) -> SettingsStore { SettingsStore(defaults: defaults) }

    @Test func savesTheChoice() {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        let settings = store(defaults)
        #expect(settings.nowPlayingAppMode == .all)
        #expect(settings.mediaAppFilter.mode == .all)

        settings.nowPlayingAppMode = .chosen
        settings.setNowPlaying("com.spotify.client", allowed: true)
        settings.setNowPlaying("com.spotify.client", allowed: true)
        settings.setNowPlaying("", allowed: true)
        settings.noteMediaApp("com.google.Chrome")
        settings.noteMediaApp("com.spotify.client")

        let reopened = store(defaults)
        #expect(reopened.nowPlayingAppMode == .chosen)
        #expect(reopened.nowPlayingApps == ["com.spotify.client"])
        #expect(reopened.recentMediaApps.identifiers == ["com.spotify.client", "com.google.Chrome"])
        #expect(reopened.mediaAppFilter.allows("com.spotify.client"))
        #expect(!reopened.mediaAppFilter.allows("com.google.Chrome"))

        reopened.forgetMediaApp("com.spotify.client")
        #expect(reopened.nowPlayingApps.isEmpty)
        #expect(reopened.recentMediaApps.identifiers == ["com.google.Chrome"])
    }

    @Test func ignoresABrokenSavedMode() {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        defaults.set("everything", forKey: "nowPlaying.appMode")
        defaults.set(["a", "a", ""], forKey: "nowPlaying.apps")
        let settings = store(defaults)
        #expect(settings.nowPlayingAppMode == .all)
        #expect(settings.nowPlayingApps == ["a"])
    }
}
