import Foundation

public struct NowPlayingInfo: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval?
    /// Position when the player last reported it, at `sampledAt`.
    public var elapsed: TimeInterval?
    public var sampledAt: Date?
    public var playbackRate: Double
    public var isPlaying: Bool
    public var bundleIdentifier: String?
    public var processIdentifier: Int32?
    public var artworkKey: String?

    public init(
        title: String,
        artist: String = "",
        album: String = "",
        duration: TimeInterval? = nil,
        elapsed: TimeInterval? = nil,
        sampledAt: Date? = nil,
        playbackRate: Double = 0,
        isPlaying: Bool = false,
        bundleIdentifier: String? = nil,
        processIdentifier: Int32? = nil,
        artworkKey: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.elapsed = elapsed
        self.sampledAt = sampledAt
        self.playbackRate = playbackRate
        self.isPlaying = isPlaying
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.artworkKey = artworkKey
    }

    public var hasContent: Bool {
        !title.isEmpty || !artist.isEmpty
    }

    /// Players report position only when something changes, so the live position is
    /// extrapolated from the last sample.
    public func elapsed(at date: Date) -> TimeInterval? {
        guard let elapsed else { return nil }
        var value = elapsed
        if isPlaying, let sampledAt {
            let rate = playbackRate > 0 ? playbackRate : 1
            value += max(0, date.timeIntervalSince(sampledAt)) * rate
        }
        if let duration, duration > 0 {
            value = min(value, duration)
        }
        return max(0, value)
    }

    /// 0…1, or nil for live streams and players that don't report length.
    public func progress(at date: Date) -> Double? {
        guard let duration, duration > 0, let elapsed = elapsed(at: date) else { return nil }
        return min(max(elapsed / duration, 0), 1)
    }
}

/// One line of output from the media helper.
public enum BridgeMessage: Equatable, Sendable {
    case ready
    case error(String)
    /// `info` is nil when nothing is playing. `artwork` is only present when it changed.
    case nowPlaying(info: NowPlayingInfo?, artwork: Data?)

    /// The line reader has an 8 MiB limit; retain at most half of that as decoded artwork.
    public static let maximumArtworkBytes = 4 * 1024 * 1024
    public static let maximumTextLength = 4_096

    public static func parse(_ line: Data) -> BridgeMessage? {
        guard
            let object = try? JSONSerialization.jsonObject(with: line),
            let dictionary = object as? [String: Any],
            let type = dictionary["type"] as? String
        else { return nil }

        switch type {
        case "ready":
            return .ready
        case "error":
            return .error(boundedText(dictionary["message"] as? String))
        case "nowPlaying":
            return parseNowPlaying(dictionary)
        default:
            return nil
        }
    }

    private static func parseNowPlaying(_ dictionary: [String: Any]) -> BridgeMessage {
        let artwork = (dictionary["artwork"] as? String)
            .flatMap { Data(base64Encoded: $0) }
            .flatMap { $0.count <= maximumArtworkBytes ? $0 : nil }
        let title = boundedText(dictionary["title"] as? String)
        let artist = boundedText(dictionary["artist"] as? String)
        guard (dictionary["hasInfo"] as? Bool) == true, !title.isEmpty || !artist.isEmpty else {
            return .nowPlaying(info: nil, artwork: nil)
        }

        let pid = (dictionary["pid"] as? NSNumber)?.int32Value
        let info = NowPlayingInfo(
            title: title,
            artist: artist,
            album: boundedText(dictionary["album"] as? String),
            duration: finitePositive(dictionary["duration"]),
            elapsed: finiteNonNegative(dictionary["elapsed"]),
            sampledAt: finitePositive(dictionary["timestamp"]).map(Date.init(timeIntervalSince1970:)),
            playbackRate: (dictionary["rate"] as? NSNumber)?.doubleValue ?? 0,
            isPlaying: (dictionary["playing"] as? Bool) ?? false,
            bundleIdentifier: (dictionary["bundleID"] as? String).flatMap { boundedText($0).isEmpty ? nil : boundedText($0) },
            processIdentifier: (pid ?? 0) > 0 ? pid : nil,
            artworkKey: boundedText(dictionary["artworkKey"] as? String)
        )
        return .nowPlaying(info: info, artwork: artwork)
    }

    private static func boundedText(_ value: String?) -> String {
        guard let value else { return "" }
        return String(value.prefix(maximumTextLength))
    }

    private static func finitePositive(_ value: Any?) -> Double? {
        guard let number = (value as? NSNumber)?.doubleValue, number.isFinite, number > 0 else { return nil }
        return number
    }

    private static func finiteNonNegative(_ value: Any?) -> Double? {
        guard let number = (value as? NSNumber)?.doubleValue, number.isFinite, number >= 0 else { return nil }
        return number
    }
}
