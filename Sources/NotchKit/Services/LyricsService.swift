import Foundation
import Observation

/// Finds timed lyrics for the song that's playing, from LRCLIB. Only the song's title, artist,
/// album and length are sent; nothing about you. Each song is looked up once per launch, and a
/// song without timed lyrics simply shows none.
@MainActor
@Observable
public final class LyricsService {
    /// Lyrics for the song now playing, or nil when there are none (or none yet).
    public private(set) var current: SyncedLyrics?

    @ObservationIgnored private var currentKey: LyricsLookup.Key?
    /// Answers so far, including "none" (nil), so a song isn't asked about twice.
    @ObservationIgnored private var cache: [LyricsLookup.Key: SyncedLyrics?] = [:]
    @ObservationIgnored private var cacheOrder: [LyricsLookup.Key] = []
    @ObservationIgnored private var lookup: Task<Void, Never>?
    @ObservationIgnored private let session: URLSession

    private static let cacheLimit = 100

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Call when the song changes. Pass nil (or switch lyrics off) to clear.
    public func update(for info: NowPlayingInfo?, enabled: Bool) {
        let key = enabled ? info.flatMap(LyricsLookup.Key.init) : nil
        guard key != currentKey else { return }
        currentKey = key
        lookup?.cancel()
        lookup = nil
        guard let key else {
            current = nil
            return
        }
        if let cached = cache[key] {
            current = cached
            return
        }
        current = nil
        lookup = Task { [weak self, session] in
            // A short wait, so skipping through songs doesn't send a request for each one.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            let found = await Self.fetch(key, session: session)
            guard !Task.isCancelled, let self else { return }
            // A failed request (offline) isn't remembered, so it's tried again next time.
            if case .some(let lyrics) = found { self.remember(lyrics, for: key) }
            if self.currentKey == key { self.current = found ?? nil }
        }
    }

    private func remember(_ lyrics: SyncedLyrics?, for key: LyricsLookup.Key) {
        cache[key] = .some(lyrics)
        cacheOrder.append(key)
        if cacheOrder.count > Self.cacheLimit {
            cache[cacheOrder.removeFirst()] = nil
        }
    }

    /// The outer optional is nil when the lookup failed; the inner one when the song has no
    /// timed lyrics.
    nonisolated private static func fetch(_ key: LyricsLookup.Key, session: URLSession) async -> SyncedLyrics?? {
        // The exact match first; then a search, for songs whose album or length differ a little.
        if let url = LyricsLookup.getURL(for: key) {
            switch await request(url, as: LyricsLookup.Record.self, session: session) {
            case .found(let record):
                if let lyrics = LyricsLookup.lyrics(from: record, for: key) { return .some(lyrics) }
            case .notFound:
                break
            case .failed:
                return nil
            }
        }
        if let url = LyricsLookup.searchURL(for: key) {
            switch await request(url, as: [LyricsLookup.Record].self, session: session) {
            case .found(let records):
                return .some(records.lazy.compactMap { LyricsLookup.lyrics(from: $0, for: key) }.first)
            case .notFound:
                return .some(nil)
            case .failed:
                return nil
            }
        }
        return .some(nil)
    }

    private enum Response<Value> {
        case found(Value)
        case notFound
        case failed
    }

    nonisolated private static func request<Value: Decodable>(_ url: URL, as type: Value.Type, session: URLSession) async -> Response<Value> {
        var request = URLRequest(url: url, timeoutInterval: 10)
        // LRCLIB asks apps to say who they are.
        request.setValue("Dynamic Ledge (https://github.com/shandilyaswagat/dynamic_ledge)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode else { return .failed }
        if status == 404 { return .notFound }
        guard status == 200, let value = try? JSONDecoder().decode(Value.self, from: data) else { return .failed }
        return .found(value)
    }
}
