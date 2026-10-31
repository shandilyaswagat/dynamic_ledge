import Foundation

public struct WeatherPlace: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let country: String?
    public let admin1: String?
    public var label: String { [name, admin1, country].compactMap { $0 }.joined(separator: ", ") }
}

struct WeatherSearch: Decodable { let results: [WeatherPlace]? }
struct WeatherResponse: Decodable {
    let current: Current
    struct Current: Decodable {
        let temperature_2m: Double
        let apparent_temperature: Double
    }
}
struct LyricsResponse: Decodable {
    let plainLyrics: String?
    let syncedLyrics: String?
    let instrumental: Bool?
}

public struct LyricLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public let time: TimeInterval
    public let text: String

    public init(id: Int, time: TimeInterval, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }
}

public struct ParsedLyrics: Equatable, Sendable {
    public let plain: String
    public let lines: [LyricLine]

    public init(plain: String = "", lines: [LyricLine] = []) {
        self.plain = plain
        self.lines = lines
    }

    public var isSynced: Bool { !lines.isEmpty }

    /// Finds the index of the line currently playing at the elapsed track time.
    public func activeIndex(at elapsed: TimeInterval) -> Int? {
        guard !lines.isEmpty, elapsed >= lines[0].time else { return nil }
        // Binary search or linear search for last line with time <= elapsed
        var low = 0
        var high = lines.count - 1
        var best = 0
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= elapsed {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return best
    }

    public func activeLine(at elapsed: TimeInterval) -> LyricLine? {
        guard let index = activeIndex(at: elapsed) else { return nil }
        return lines[index]
    }
}

public enum LRCParser {
    public static func parse(synced: String?, plain: String? = nil) -> ParsedLyrics {
        let plainText = plain ?? ""
        guard let synced, !synced.isEmpty else {
            return ParsedLyrics(plain: plainText, lines: [])
        }

        var parsedLines: [(time: TimeInterval, text: String)] = []
        let tagRegex = try? NSRegularExpression(pattern: #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]"#)

        for rawLine in synced.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, let regex = tagRegex else { continue }
            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            guard !matches.isEmpty else { continue }

            // Extract the lyric text after all timestamp tags
            let lastMatch = matches.last!
            let textStartIndex = line.index(line.startIndex, offsetBy: lastMatch.range.location + lastMatch.range.length)
            let text = line[textStartIndex...].trimmingCharacters(in: .whitespaces)

            for match in matches {
                guard let minRange = Range(match.range(at: 1), in: line),
                      let secRange = Range(match.range(at: 2), in: line),
                      let minutes = Double(line[minRange]),
                      let seconds = Double(line[secRange]) else { continue }

                var fraction = 0.0
                if match.numberOfRanges > 3, match.range(at: 3).location != NSNotFound,
                   let fracRange = Range(match.range(at: 3), in: line) {
                    let fracStr = String(line[fracRange])
                    if let fracVal = Double(fracStr) {
                        fraction = fracVal / pow(10.0, Double(fracStr.count))
                    }
                }
                let totalTime = (minutes * 60.0) + seconds + fraction
                parsedLines.append((time: totalTime, text: text))
            }
        }

        parsedLines.sort { $0.time < $1.time }
        let lyricLines = parsedLines.enumerated().map { index, item in
            LyricLine(id: index, time: item.time, text: item.text)
        }

        return ParsedLyrics(plain: plainText, lines: lyricLines)
    }
}

struct iTunesArtworkSearchResponse: Decodable {
    let results: [SearchResult]
    struct SearchResult: Decodable {
        let artworkUrl100: String?
    }
}

enum OnlineRequests {
    static func url(host: String, path: String, values: [String: String]) -> URL {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = path
        parts.queryItems = values.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts.url!
    }

    static func lyrics(_ info: NowPlayingInfo) -> URL? {
        guard !info.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !info.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var values = ["track_name": info.title, "artist_name": info.artist]
        if !info.album.isEmpty { values["album_name"] = info.album }
        if let duration = info.duration, duration.isFinite, duration > 0 { values["duration"] = String(duration) }
        return url(host: "lrclib.net", path: "/api/get", values: values)
    }

    static func artwork(_ info: NowPlayingInfo) -> URL? {
        guard !info.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !info.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let term = "\(info.artist) \(info.title)"
        return url(host: "itunes.apple.com", path: "/search", values: ["term": term, "entity": "song", "limit": "1"])
    }

    static func highResolutionArtworkURL(from urlString: String) -> URL? {
        let highRes = urlString.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        return URL(string: highRes)
    }
}
