import Foundation
import Testing
@testable import NotchKit

private actor RequestProbe {
    var requests: [URL] = []
    func fetch(_ url: URL) -> Data {
        requests.append(url)
        if url.host == "lrclib.net" { return Data(#"{"plainLyrics":"Test fixture line","instrumental":false}"#.utf8) }
        return Data(#"{"current":{"temperature_2m":21,"apparent_temperature":20}}"#.utf8)
    }
}

@MainActor
@Suite("Optional online features")
struct OnlineFeaturesTests {
    private func wait(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        return condition()
    }

    @Test func disabledFeaturesNeverFetchAndSettingsPersist() async {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        let probe = RequestProbe()
        let service = OnlineFeaturesService(settings: settings, fetch: { await probe.fetch($0) })
        #expect(!settings.weatherEnabled && !settings.lyricsEnabled)
        service.search(city: "London")
        service.loadLyrics(for: NowPlayingInfo(title: "Track", artist: "Artist"))
        #expect(await probe.requests.isEmpty)
        settings.weatherEnabled = true
        settings.lyricsEnabled = true
        #expect(SettingsStore(defaults: defaults).weatherEnabled)
        #expect(SettingsStore(defaults: defaults).lyricsEnabled)
        service.loadLyrics(for: NowPlayingInfo(title: "Track", artist: "Artist"))
        #expect(await wait { service.lyrics != nil })
        #expect(service.lyrics == "Test fixture line")
        service.stopLyrics()
        #expect(service.lyrics == nil && service.lyricsTitle == nil && !service.lyricsLoading)
    }

    @Test func requestsEncodeMetadataAndRejectIncompleteSongs() {
        #expect(OnlineRequests.lyrics(NowPlayingInfo(title: "", artist: "Artist")) == nil)
        let url = OnlineRequests.lyrics(NowPlayingInfo(title: "A & B?", artist: "Artist/Name", duration: .infinity))!
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(url.host == "lrclib.net")
        #expect(query.first { $0.name == "track_name" }?.value == "A & B?")
        #expect(!query.contains { $0.name == "duration" })
    }

    @Test func lrcParserHandlesTimestampsAndMultipleLines() {
        let lrc = """
        [ti:Test Title]
        [ar:Test Artist]
        [00:05.50]First line
        [00:12.00][00:25.00]Repeated line
        [01:03.750]Final line
        """
        let parsed = LRCParser.parse(synced: lrc, plain: "Plain fallback")
        #expect(parsed.isSynced)
        #expect(parsed.lines.count == 4)
        #expect(parsed.lines[0].time == 5.5)
        #expect(parsed.lines[0].text == "First line")
        #expect(parsed.lines[1].time == 12.0)
        #expect(parsed.lines[1].text == "Repeated line")
        #expect(parsed.lines[2].time == 25.0)
        #expect(parsed.lines[2].text == "Repeated line")
        #expect(parsed.lines[3].time == 63.75)
        #expect(parsed.lines[3].text == "Final line")

        #expect(parsed.activeIndex(at: 0.0) == nil)
        #expect(parsed.activeIndex(at: 5.4) == nil)
        #expect(parsed.activeIndex(at: 5.5) == 0)
        #expect(parsed.activeIndex(at: 10.0) == 0)
        #expect(parsed.activeIndex(at: 12.0) == 1)
        #expect(parsed.activeIndex(at: 20.0) == 1)
        #expect(parsed.activeIndex(at: 25.0) == 2)
        #expect(parsed.activeIndex(at: 70.0) == 3)
    }

    @Test func weatherUsesChosenCoordinatesAndClearsWhenStopped() async {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        settings.weatherEnabled = true
        let probe = RequestProbe()
        let service = OnlineFeaturesService(settings: settings, fetch: { await probe.fetch($0) })
        let place = WeatherPlace(id: 1, name: "Test city", latitude: 12, longitude: 34, country: "Country", admin1: nil)
        service.forecast(for: place)
        #expect(await wait { service.weather != nil })
        #expect(settings.weatherPlace == place)
        #expect(SettingsStore(defaults: defaults).weatherPlace == place)
        let url = await probe.requests.first
        #expect(url?.host == "api.open-meteo.com")
        service.stopWeather()
        #expect(service.weather == nil && service.places.isEmpty && !service.weatherLoading)
    }
}

private actor PendingLyrics {
    var waiting: [String: CheckedContinuation<Data, Never>] = [:]
    func fetch(_ url: URL) async -> Data {
        let title = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "track_name" }!.value!
        return await withCheckedContinuation { waiting[title] = $0 }
    }
    func contains(_ title: String) -> Bool { waiting[title] != nil }
    func finish(_ title: String) {
        waiting.removeValue(forKey: title)?.resume(returning: Data(#"{"plainLyrics":"Fixture","instrumental":false}"#.utf8))
    }
}

extension OnlineFeaturesTests {
    @Test func lateResponsesCannotRestoreStoppedLyrics() async {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        settings.lyricsEnabled = true
        let pending = PendingLyrics()
        let service = OnlineFeaturesService(settings: settings, fetch: { await pending.fetch($0) })
        service.loadLyrics(for: NowPlayingInfo(title: "Old", artist: "Artist"))
        let deadline = ContinuousClock.now + .seconds(3)
        while !(await pending.contains("Old")), ContinuousClock.now < deadline { await Task.yield() }
        #expect(await pending.contains("Old"))
        service.stopLyrics()
        await pending.finish("Old")
        service.loadLyrics(for: NowPlayingInfo(title: "New", artist: "Artist"))
        let nextDeadline = ContinuousClock.now + .seconds(3)
        while !(await pending.contains("New")), ContinuousClock.now < nextDeadline { await Task.yield() }
        #expect(await pending.contains("New"))
        await pending.finish("New")
        #expect(await wait { service.lyrics != nil })
        #expect(service.lyricsTitle == "New")
        service.stopLyrics()
    }
}
