import Foundation

/// The tiles of the launcher grid, in order, each with its keyboard shortcut (⌃⌥ + key).
public enum LauncherItem: String, CaseIterable, Sendable, Identifiable {
    case nowPlaying
    case timer
    case stopwatch
    case calendar
    case reminders
    case clipboard
    case files
    case scratchpad
    case mirror
    case keepAwake
    case stats

    public var id: String { rawValue }

    /// The letter pressed with Control and Option. Chosen to stay clear of the window
    /// managers' usual Control-Option keys (arrows, C, D, E, F, G, T, U, I, J, K).
    public var key: Character {
        switch self {
        case .nowPlaying: "M"
        case .timer: "R"
        case .stopwatch: "S"
        case .calendar: "A"
        case .reminders: "O"
        case .clipboard: "B"
        case .files: "L"
        case .scratchpad: "N"
        case .mirror: "W"
        case .keepAwake: "Z"
        case .stats: "P"
        }
    }

    /// "⌃⌥M", as shown on the tile.
    public var shortcutLabel: String { "⌃⌥" + String(key) }
}
