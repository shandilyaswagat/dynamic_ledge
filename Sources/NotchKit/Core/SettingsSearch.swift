import Foundation

/// A destination shown when searching Settings. Results open a page containing the setting.
enum SettingsSearchPage: String, Sendable {
    case general, about, update, media, coding, appearance, home, activities
}

struct SettingsSearchResult: Identifiable, Sendable {
    let title: String
    let path: String
    let page: SettingsSearchPage
    let keywords: String
    var id: String { "\(page.rawValue):\(title)" }
}

enum SettingsSearch {
    static let entries: [SettingsSearchResult] = [
        .init(title: "General", path: "General", page: .general, keywords: "settings notch behavior"),
        .init(title: "About", path: "General", page: .about, keywords: "version build license talvioh"),
        .init(title: "Software Update", path: "General", page: .update, keywords: "version update install automatically github"),
        .init(title: "Now Playing", path: "General", page: .media, keywords: "music podcasts video audio playback player"),
        .init(title: "Lyrics", path: "General › Now Playing", page: .media, keywords: "songs music subtitles"),
        .init(title: "Live music bars", path: "General › Now Playing", page: .media, keywords: "spectrum equalizer visualizer waveform audio levels"),
        .init(title: "Music apps", path: "General › Now Playing", page: .media, keywords: "media browser spotify youtube filter"),
        .init(title: "Coding Assistants", path: "General", page: .coding, keywords: "claude codex copilot cursor antigravity approval"),
        .init(title: "AI Agent Usage", path: "General › Coding Assistants", page: .coding, keywords: "tokens quota rate limits reset codex antigravity"),
        .init(title: "Open at login", path: "General", page: .general, keywords: "startup launch automatically"),
        .init(title: "Display", path: "General", page: .general, keywords: "screen monitor built in external"),
        .init(title: "Lock Screen", path: "General", page: .general, keywords: "locked screen"),
        .init(title: "Keyboard shortcuts", path: "General", page: .general, keywords: "hotkeys keyboard"),
        .init(title: "Appearance", path: "Appearance", page: .appearance, keywords: "theme look black glass"),
        .init(title: "Home layout", path: "Appearance", page: .appearance, keywords: "standard elongated wide size"),
        .init(title: "Displays Without a Notch", path: "Appearance", page: .appearance, keywords: "pill island dynamic external monitor notch"),
        .init(title: "Home & Widgets", path: "Home & Widgets", page: .home, keywords: "home features"),
        .init(title: "File Tray", path: "Home & Widgets", page: .home, keywords: "files drop drag"),
        .init(title: "Clipboard", path: "Home & Widgets", page: .home, keywords: "copy paste history"),
        .init(title: "Text from images", path: "Home & Widgets", page: .home, keywords: "ocr scan screenshot recognise recognize copy"),
        .init(title: "Calendar", path: "Home & Widgets", page: .home, keywords: "events meetings"),
        .init(title: "Notes and Reminders", path: "Home & Widgets", page: .home, keywords: "notes reminders tasks"),
        .init(title: "Mirror and Stats", path: "Home & Widgets", page: .home, keywords: "camera cpu memory network"),
        .init(title: "Shortcuts", path: "Home & Widgets", page: .home, keywords: "apple siri favorites automation"),
        .init(title: "Activities & Alerts", path: "Activities & Alerts", page: .activities, keywords: "notifications"),
        .init(title: "Timer and Focus", path: "Activities & Alerts", page: .activities, keywords: "timer stopwatch pomodoro break"),
        .init(title: "Calls & Microphone", path: "Activities & Alerts", page: .activities, keywords: "meeting camera call mic"),
        .init(title: "Battery and Charging", path: "Activities & Alerts", page: .activities, keywords: "battery charging power alert"),
        .init(title: "Volume & Brightness", path: "Activities & Alerts", page: .activities, keywords: "sound volume brightness level"),
        .init(title: "AirDrop", path: "Activities & Alerts", page: .activities, keywords: "share files"),
    ]

    static func results(for query: String) -> [SettingsSearchResult] {
        let terms = query.split(whereSeparator: \.isWhitespace)
        guard !terms.isEmpty else { return [] }
        return entries.filter { entry in
            let text = "\(entry.title) \(entry.path) \(entry.keywords)"
            return terms.allSatisfy { text.localizedCaseInsensitiveContains(String($0)) }
        }
    }
}
