import Foundation
import Observation

/// On-demand requests only. Disabling a feature cancels its work and clears its results.
@MainActor
@Observable
public final class OnlineFeaturesService {
    public private(set) var places: [WeatherPlace] = []
    public private(set) var weather: String?
    public private(set) var weatherMessage: String?
    public private(set) var weatherLoading = false
    public private(set) var lyrics: String?
    public private(set) var parsedLyrics: ParsedLyrics?
    public private(set) var lyricsMessage: String?
    public private(set) var lyricsLoading = false
    public private(set) var lyricsTitle: String?
    public private(set) var onlineArtworkData: Data?
    private let settings: SettingsStore
    @ObservationIgnored private let fetch: @Sendable (URL) async throws -> Data
    @ObservationIgnored private var weatherTask: Task<Void, Never>?
    @ObservationIgnored private var lyricsTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    private var weatherGeneration = 0
    private var lyricsGeneration = 0
    private var artworkGeneration = 0

    public init(settings: SettingsStore, fetch: @escaping @Sendable (URL) async throws -> Data = OnlineFeaturesService.download) {
        self.settings = settings
        self.fetch = fetch
    }

    public nonisolated static func download(_ url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("DynamicLedge/1.4 (optional weather and lyrics)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), data.count <= 2_000_000 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    public func search(city: String) {
        stopWeather()
        let city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard settings.weatherEnabled, city.count >= 2 else { return }
        let generation = weatherGeneration
        weatherLoading = true
        let url = OnlineRequests.url(host: "geocoding-api.open-meteo.com", path: "/v1/search", values: ["name": city, "count": "5", "language": "en", "format": "json"])
        weatherTask = Task { [weak self, fetch] in
            do {
                let data = try await fetch(url)
                let result = try JSONDecoder().decode(WeatherSearch.self, from: data)
                guard let self, !Task.isCancelled, self.settings.weatherEnabled, self.weatherGeneration == generation else { return }
                self.places = result.results ?? []
                self.weatherMessage = self.places.isEmpty ? String(localized: "No cities found. Try another name.") : nil
                self.weatherLoading = false
            } catch {
                guard let self, !Task.isCancelled, self.weatherGeneration == generation else { return }
                self.weatherMessage = String(localized: "Couldn’t find cities. Check your connection and try again.")
                self.weatherLoading = false
            }
        }
    }

    public func forecast(for place: WeatherPlace) {
        stopWeather()
        guard settings.weatherEnabled, place.latitude.isFinite, place.longitude.isFinite,
              (-90...90).contains(place.latitude), (-180...180).contains(place.longitude) else { return }
        settings.weatherPlace = place
        let generation = weatherGeneration
        weatherLoading = true
        let url = OnlineRequests.url(host: "api.open-meteo.com", path: "/v1/forecast", values: ["latitude": String(place.latitude), "longitude": String(place.longitude), "current": "temperature_2m,apparent_temperature"])
        weatherTask = Task { [weak self, fetch] in
            do {
                let data = try await fetch(url)
                let result = try JSONDecoder().decode(WeatherResponse.self, from: data)
                guard let self, !Task.isCancelled, self.settings.weatherEnabled, self.weatherGeneration == generation else { return }
                self.weather = String(format: String(localized: "%.0f°C · Feels like %.0f°C"), result.current.temperature_2m, result.current.apparent_temperature)
                self.weatherLoading = false
            } catch {
                guard let self, !Task.isCancelled, self.weatherGeneration == generation else { return }
                self.weatherMessage = String(localized: "Weather unavailable. Check your connection and try again.")
                self.weatherLoading = false
            }
        }
    }

    public func loadLyrics(for info: NowPlayingInfo?) {
        stopLyrics()
        guard settings.lyricsEnabled else { return }
        guard let info, let url = OnlineRequests.lyrics(info) else {
            lyricsMessage = String(localized: "Play a song with a title and artist to find lyrics.")
            return
        }
        let generation = lyricsGeneration
        lyricsTitle = info.title
        lyricsLoading = true
        lyricsTask = Task { [weak self, fetch] in
            do {
                let data = try await fetch(url)
                let result = try JSONDecoder().decode(LyricsResponse.self, from: data)
                guard let self, !Task.isCancelled, self.settings.lyricsEnabled, self.lyricsGeneration == generation else { return }
                self.lyrics = result.plainLyrics
                self.parsedLyrics = LRCParser.parse(synced: result.syncedLyrics, plain: result.plainLyrics)
                if result.instrumental == true { self.lyricsMessage = String(localized: "Instrumental track") }
                else if result.plainLyrics?.isEmpty != false && result.syncedLyrics?.isEmpty != false { self.lyricsMessage = String(localized: "No lyrics found for this song.") }
                self.lyricsLoading = false
            } catch {
                guard let self, !Task.isCancelled, self.lyricsGeneration == generation else { return }
                self.lyricsMessage = String(localized: "Lyrics unavailable. Try again or choose another song.")
                self.lyricsLoading = false
            }
        }
    }

    public func stopWeather() {
        weatherGeneration += 1
        weatherTask?.cancel(); weatherTask = nil
        places = []; weather = nil; weatherMessage = nil; weatherLoading = false
    }

    public func stopLyrics() {
        lyricsGeneration += 1
        lyricsTask?.cancel(); lyricsTask = nil
        lyrics = nil; parsedLyrics = nil; lyricsMessage = nil; lyricsTitle = nil; lyricsLoading = false
    }

    public func loadArtwork(for info: NowPlayingInfo?) {
        stopArtwork()
        guard settings.onlineArtworkEnabled, let info, let searchURL = OnlineRequests.artwork(info) else { return }
        let generation = artworkGeneration
        artworkTask = Task { [weak self, fetch] in
            do {
                let searchData = try await fetch(searchURL)
                let searchResult = try JSONDecoder().decode(iTunesArtworkSearchResponse.self, from: searchData)
                guard let first = searchResult.results.first,
                      let urlStr = first.artworkUrl100,
                      let highResURL = OnlineRequests.highResolutionArtworkURL(from: urlStr) else { return }
                let imageData = try await fetch(highResURL)
                guard let self, !Task.isCancelled, self.settings.onlineArtworkEnabled, self.artworkGeneration == generation else { return }
                self.onlineArtworkData = imageData
            } catch {
                // Silently ignore artwork failures - falls back to local artwork
            }
        }
    }

    public func stopArtwork() {
        artworkGeneration += 1
        artworkTask?.cancel(); artworkTask = nil
        onlineArtworkData = nil
    }
}
