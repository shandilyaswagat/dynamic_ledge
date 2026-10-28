import Foundation

/// Lyrics timed to the song, line by line, from an LRC file ("[01:23.45] words").
public struct SyncedLyrics: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var time: TimeInterval
        /// Empty for an instrumental gap.
        public var text: String
    }

    public let lines: [Line]

    /// Nil when there's nothing timed in it (plain lyrics, or only tags like [ar:Artist]).
    public init?(lrc: String) {
        var lines: [Line] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            var rest = Substring(raw)
            var times: [TimeInterval] = []
            // A line can carry several stamps when it repeats: [00:12.00][01:15.00] words
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let stamp = rest[rest.index(after: rest.startIndex)..<close]
                guard let time = Self.seconds(stamp) else { break }
                times.append(time)
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            lines += times.map { Line(time: $0, text: text) }
        }
        guard lines.contains(where: { !$0.text.isEmpty }) else { return nil }
        self.lines = lines.sorted { $0.time < $1.time }
    }

    /// The line being sung at `elapsed`, or nil before the first one.
    public func index(at elapsed: TimeInterval) -> Int? {
        // The last line whose time has come; lines are sorted, so search from the end.
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= elapsed {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// "mm:ss", "mm:ss.xx" or "mm:ss:xx". Tags like "ar:Artist" aren't times.
    private static func seconds(_ stamp: Substring) -> TimeInterval? {
        let parts = stamp.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let minutes = Double(parts[0]) else { return nil }
        let secondsPart = parts[1].replacingOccurrences(of: ":", with: ".")
        guard let seconds = Double(secondsPart), seconds < 60 else { return nil }
        return minutes * 60 + seconds
    }
}

/// Matching a playing track to lyrics from LRCLIB (lrclib.net), a free, open lyrics database.
public enum LyricsLookup {
    /// What identifies a track: lyrics are looked up once per key.
    public struct Key: Hashable, Sendable {
        public var title: String
        public var artist: String
        public var album: String
        /// Rounded to whole seconds; nil when the player doesn't say.
        public var duration: Int?

        public init?(_ info: NowPlayingInfo) {
            let title = info.title.trimmingCharacters(in: .whitespaces)
            let artist = info.artist.trimmingCharacters(in: .whitespaces)
            // Without an artist (most web videos) a match would be a guess.
            guard !title.isEmpty, !artist.isEmpty else { return nil }
            self.title = title
            self.artist = artist
            album = info.album.trimmingCharacters(in: .whitespaces)
            duration = info.duration.map { Int($0.rounded()) }
        }
    }

    public static func getURL(for key: Key) -> URL? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var items = [
            URLQueryItem(name: "track_name", value: key.title),
            URLQueryItem(name: "artist_name", value: key.artist),
        ]
        if !key.album.isEmpty { items.append(URLQueryItem(name: "album_name", value: key.album)) }
        if let duration = key.duration { items.append(URLQueryItem(name: "duration", value: String(duration))) }
        components?.queryItems = items
        return components?.url
    }

    public static func searchURL(for key: Key) -> URL? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "track_name", value: key.title),
            URLQueryItem(name: "artist_name", value: key.artist),
        ]
        return components?.url
    }

    /// One LRCLIB record.
    public struct Record: Decodable, Sendable {
        public var duration: Double?
        public var instrumental: Bool?
        public var syncedLyrics: String?
    }

    /// Timed lyrics from a record, if it has them and its length is close to the track's
    /// (a live or extended version would be out of step).
    public static func lyrics(from record: Record, for key: Key) -> SyncedLyrics? {
        guard record.instrumental != true, let lrc = record.syncedLyrics else { return nil }
        if let wanted = key.duration, let duration = record.duration, abs(duration - Double(wanted)) > 3 {
            return nil
        }
        return SyncedLyrics(lrc: lrc)
    }
}
