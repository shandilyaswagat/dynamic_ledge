import Foundation

/// Finds the video-call link in a calendar event, so the notch can offer a Join button.
public enum MeetingLinks {
    public enum Provider: String, Sendable, CaseIterable {
        case meet = "Meet"
        case zoom = "Zoom"
        case teams = "Teams"
        case webex = "Webex"
    }

    /// The first Meet, Zoom, Teams or Webex link in the event's URL, location or notes.
    public static func joinLink(in texts: [String?]) -> (url: URL, provider: Provider)? {
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            for match in links(in: text) {
                if let provider = provider(for: match) { return (match, provider) }
            }
        }
        return nil
    }

    public static func provider(for url: URL) -> Provider? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()
        if host == "meet.google.com", path.count > 1 { return .meet }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") {
            return path.hasPrefix("/j/") || path.hasPrefix("/my/") || path.hasPrefix("/w/") ? .zoom : nil
        }
        if host == "teams.microsoft.com" || host == "teams.live.com" {
            return path.contains("meetup-join") || path.hasPrefix("/meet") || path.hasPrefix("/l/meet") ? .teams : nil
        }
        if host.hasSuffix(".webex.com") { return path.count > 1 ? .webex : nil }
        return nil
    }

    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
    }
}
