import Foundation
import Observation

/// Where the notch shows up.
public enum DisplayChoice: Hashable, Sendable, Identifiable {
    /// The built-in display if it has a notch, otherwise the main display.
    case automatic
    /// The display that holds the menu bar.
    case main
    /// Whichever display the pointer is on: the notch on the built-in screen, an island elsewhere.
    case followPointer
    /// One particular display, remembered by its UUID; falls back to automatic when unplugged.
    case specific(String)
    /// Every connected display at once. Things you open appear on the screen you're using.
    case all

    public var id: String { rawValue }

    public var rawValue: String {
        switch self {
        case .automatic: "automatic"
        case .main: "main"
        case .followPointer: "followPointer"
        case .specific(let uuid): "display:" + uuid
        case .all: "all"
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "automatic": self = .automatic
        case "main": self = .main
        case "followPointer": self = .followPointer
        case "all": self = .all
        default:
            guard rawValue.hasPrefix("display:"), rawValue.count > 8 else { return nil }
            self = .specific(String(rawValue.dropFirst(8)))
        }
    }
}

/// Controls how a closed notch opens. In hover mode only the opening trigger changes: once
/// open, every control remains clickable and accessible.
public enum NotchOpenMode: String, CaseIterable, Sendable, Identifiable {
    case click
    case hover

    public var id: String { rawValue }
}

/// User preferences, saved to UserDefaults as soon as they change.
@MainActor
@Observable
public final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults

    public var appearance: NotchAppearance {
        didSet {
            // The layout engine clamps too, so out-of-range values can never reach the screen.
            let value = appearance.clamped()
            defaults.set(value.pitchBlack, forKey: Key.pitchBlack)
            defaults.set(value.size.rawValue, forKey: Key.size)
            defaults.set(value.nookLayout.rawValue, forKey: Key.nookLayout)
            defaults.set(value.width, forKey: Key.width)
            defaults.set(value.height, forKey: Key.height)
        }
    }

    public var showWhenIdle: Bool { didSet { defaults.set(showWhenIdle, forKey: Key.showWhenIdle) } }
    public var notchOpenMode: NotchOpenMode { didSet { defaults.set(notchOpenMode.rawValue, forKey: Key.notchOpenMode) } }
    public var hoverDelay: Double {
        didSet {
            let clamped = max(0.1, min(0.5, (hoverDelay * 100).rounded() / 100))
            if hoverDelay != clamped { hoverDelay = clamped }
            defaults.set(hoverDelay, forKey: Key.hoverDelay)
        }
    }
    public var collapseOnPointerExit: Bool { didSet { defaults.set(collapseOnPointerExit, forKey: Key.collapseOnPointerExit) } }
    public var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) } }
    public var liquidAnimations: Bool { didSet { defaults.set(liquidAnimations, forKey: Key.liquid) } }
    public var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Key.menuBarIcon) } }
    public var display: DisplayChoice { didSet { defaults.set(display.rawValue, forKey: Key.display) } }
    public var timerSound: Bool { didSet { defaults.set(timerSound, forKey: Key.timerSound) } }

    public var nowPlayingEnabled: Bool { didSet { defaults.set(nowPlayingEnabled, forKey: Key.nowPlaying) } }
    /// Timed lyrics under the song, looked up on LRCLIB.
    public var lyricsEnabled: Bool { didSet { defaults.set(lyricsEnabled, forKey: Key.lyrics) } }
    public var timerEnabled: Bool { didSet { defaults.set(timerEnabled, forKey: Key.timer) } }
    public var callsEnabled: Bool { didSet { defaults.set(callsEnabled, forKey: Key.calls) } }
    public var airDropEnabled: Bool { didSet { defaults.set(airDropEnabled, forKey: Key.airDrop) } }
    public var chargingAlertsEnabled: Bool { didSet { defaults.set(chargingAlertsEnabled, forKey: Key.charging) } }
    public var lowBatteryAlertsEnabled: Bool { didSet { defaults.set(lowBatteryAlertsEnabled, forKey: Key.lowBattery) } }
    public var headphoneAlertsEnabled: Bool { didSet { defaults.set(headphoneAlertsEnabled, forKey: Key.headphones) } }
    public var trayEnabled: Bool { didSet { defaults.set(trayEnabled, forKey: Key.tray) } }
    public var mirrorEnabled: Bool { didSet { defaults.set(mirrorEnabled, forKey: Key.mirror) } }
    /// Keep a history of copied text (memory only, passwords skipped).
    public var clipboardEnabled: Bool { didSet { defaults.set(clipboardEnabled, forKey: Key.clipboard) } }
    public var notesEnabled: Bool { didSet { defaults.set(notesEnabled, forKey: Key.notes) } }
    /// Show a heads-up when a download finishes. Off until asked for: macOS asks for Downloads access.
    public var downloadsEnabled: Bool { didSet { defaults.set(downloadsEnabled, forKey: Key.downloads) } }
    public var remindersEnabled: Bool { didSet { defaults.set(remindersEnabled, forKey: Key.reminders) } }
    /// Live memory and CPU beside the camera when nothing else is on, plus the Stats view.
    /// Off until asked for, since it keeps the notch showing.
    public var statsEnabled: Bool { didSet { defaults.set(statsEnabled, forKey: Key.stats) } }
    /// Show music, a running timer or charging on the Lock Screen. Off until asked for: anyone at
    /// the Mac can see it, and it relies on private window-server calls.
    public var lockScreenEnabled: Bool { didSet { defaults.set(lockScreenEnabled, forKey: Key.lockScreen) } }
    /// ⌃⌥ shortcuts for the launcher's tiles.
    public var keyboardShortcutsEnabled: Bool { didSet { defaults.set(keyboardShortcutsEnabled, forKey: Key.keyboardShortcuts) } }
    /// Look for a new version on GitHub once a day.
    public var checksForUpdates: Bool { didSet { defaults.set(checksForUpdates, forKey: Key.checksForUpdates) } }
    /// Focus session length and the break after it, in minutes.
    public var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: Key.focusMinutes) } }
    public var breakMinutes: Int { didSet { defaults.set(breakMinutes, forKey: Key.breakMinutes) } }
    public var calendarEnabled: Bool { didSet { defaults.set(calendarEnabled, forKey: Key.calendar) } }
    public var shortcutsEnabled: Bool { didSet { defaults.set(shortcutsEnabled, forKey: Key.shortcuts) } }
    /// Shortcut names pinned to the Home tab, in order.
    public var favoriteShortcuts: [String] { didSet { defaults.set(favoriteShortcuts, forKey: Key.favoriteShortcuts) } }
    /// Optional feature shortcuts beside the permanent Home shortcut, in display order.
    public var featureShortcuts: [LauncherItem] {
        didSet {
            let normalized = FeatureShortcutSelection(items: featureShortcuts).items
            if normalized != featureShortcuts {
                featureShortcuts = normalized
            } else {
                defaults.set(featureShortcuts.map(\.rawValue), forKey: Key.featureShortcuts)
            }
        }
    }
    /// Show volume and brightness changes in the notch.
    public var levelsEnabled: Bool { didSet { defaults.set(levelsEnabled, forKey: Key.levels) } }

    public static let maximumFavoriteShortcuts = 4
    public static let maximumFeatureShortcuts = FeatureShortcutSelection.maximumItems
    public static let defaultFeatureShortcuts = FeatureShortcutSelection.defaultItems
    public static let focusChoices = [15, 25, 45, 50, 60]
    public static let breakChoices = [5, 10, 15]

    /// Whether the user has explicitly customized their shortcuts. When false, the default shortcuts
    /// matching earlier versions (Files and Clipboard) are preserved.
    public var hasCustomizedFeatureShortcuts: Bool {
        defaults.object(forKey: Key.featureShortcuts) != nil
    }

    /// Set after the first-launch hint has been shown.
    public var hasShownWelcome: Bool { didSet { defaults.set(hasShownWelcome, forKey: Key.welcome) } }
    /// How long a paused track stays in the pill.
    public var pausedMediaLinger: TimeInterval { didSet { defaults.set(pausedMediaLinger, forKey: Key.linger) } }

    public static let lingerChoices: [TimeInterval] = [10, 30, 60, 300]
    public static let hoverDelayChoices: [Double] = [0.1, 0.15, 0.2, 0.25, 0.3, 0.4, 0.5]

    public static func hoverDelayLabel(_ seconds: Double) -> String {
        if abs(seconds - 0.4) < 0.001 {
            return "0.4 seconds (default)"
        }
        return String(format: "%.2g seconds", seconds)
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let standard = NotchAppearance.standard
        // The floating pill style and its position settings are gone; forget what they saved.
        for key in Key.retired { defaults.removeObject(forKey: key) }
        appearance = NotchAppearance(
            width: defaults.object(forKey: Key.width) as? Double ?? standard.width,
            height: defaults.object(forKey: Key.height) as? Double ?? standard.height,
            pitchBlack: defaults.object(forKey: Key.pitchBlack) as? Bool ?? standard.pitchBlack,
            size: defaults.string(forKey: Key.size).flatMap(NotchSize.init(rawValue:)) ?? standard.size,
            nookLayout: defaults.string(forKey: Key.nookLayout).flatMap(NookLayout.init(rawValue:)) ?? standard.nookLayout
        ).clamped()
        showWhenIdle = defaults.object(forKey: Key.showWhenIdle) as? Bool ?? false
        // Keep the behaviour of existing installations after replacing the old toggle with an
        // explicit interaction mode. New installations use click-to-open.
        if let stored = defaults.string(forKey: Key.notchOpenMode), let mode = NotchOpenMode(rawValue: stored) {
            notchOpenMode = mode
        } else {
            notchOpenMode = (defaults.object(forKey: Key.expandOnHover) as? Bool) == true ? .hover : .click
        }
        let delay = defaults.object(forKey: Key.hoverDelay) as? Double ?? 0.4
        hoverDelay = max(0.1, min(0.5, (delay * 100).rounded() / 100))
        collapseOnPointerExit = defaults.object(forKey: Key.collapseOnPointerExit) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        liquidAnimations = defaults.object(forKey: Key.liquid) as? Bool ?? true
        showMenuBarIcon = defaults.object(forKey: Key.menuBarIcon) as? Bool ?? true
        display = (defaults.string(forKey: Key.display)).flatMap(DisplayChoice.init(rawValue:)) ?? .automatic
        timerSound = defaults.object(forKey: Key.timerSound) as? Bool ?? true
        nowPlayingEnabled = defaults.object(forKey: Key.nowPlaying) as? Bool ?? true
        lyricsEnabled = defaults.object(forKey: Key.lyrics) as? Bool ?? true
        timerEnabled = defaults.object(forKey: Key.timer) as? Bool ?? true
        callsEnabled = defaults.object(forKey: Key.calls) as? Bool ?? true
        airDropEnabled = defaults.object(forKey: Key.airDrop) as? Bool ?? true
        chargingAlertsEnabled = defaults.object(forKey: Key.charging) as? Bool ?? true
        lowBatteryAlertsEnabled = defaults.object(forKey: Key.lowBattery) as? Bool ?? true
        headphoneAlertsEnabled = defaults.object(forKey: Key.headphones) as? Bool ?? true
        hasShownWelcome = defaults.bool(forKey: Key.welcome)
        trayEnabled = defaults.object(forKey: Key.tray) as? Bool ?? true
        mirrorEnabled = defaults.object(forKey: Key.mirror) as? Bool ?? true
        clipboardEnabled = defaults.object(forKey: Key.clipboard) as? Bool ?? true
        notesEnabled = defaults.object(forKey: Key.notes) as? Bool ?? true
        downloadsEnabled = defaults.object(forKey: Key.downloads) as? Bool ?? false
        remindersEnabled = defaults.object(forKey: Key.reminders) as? Bool ?? true
        statsEnabled = defaults.object(forKey: Key.stats) as? Bool ?? false
        lockScreenEnabled = defaults.object(forKey: Key.lockScreen) as? Bool ?? false
        keyboardShortcutsEnabled = defaults.object(forKey: Key.keyboardShortcuts) as? Bool ?? true
        checksForUpdates = defaults.object(forKey: Key.checksForUpdates) as? Bool ?? true
        let focus = defaults.object(forKey: Key.focusMinutes) as? Int ?? 25
        focusMinutes = Self.focusChoices.contains(focus) ? focus : 25
        let rest = defaults.object(forKey: Key.breakMinutes) as? Int ?? 5
        breakMinutes = Self.breakChoices.contains(rest) ? rest : 5
        calendarEnabled = defaults.object(forKey: Key.calendar) as? Bool ?? true
        shortcutsEnabled = defaults.object(forKey: Key.shortcuts) as? Bool ?? true
        favoriteShortcuts = Array((defaults.stringArray(forKey: Key.favoriteShortcuts) ?? []).prefix(Self.maximumFavoriteShortcuts))
        if let saved = defaults.object(forKey: Key.featureShortcuts) as? [String] {
            featureShortcuts = FeatureShortcutSelection(rawValues: saved).items
        } else {
            featureShortcuts = Self.defaultFeatureShortcuts
        }
        levelsEnabled = defaults.object(forKey: Key.levels) as? Bool ?? true
        let linger = defaults.object(forKey: Key.linger) as? Double ?? 30
        pausedMediaLinger = Self.lingerChoices.contains(linger) ? linger : 30
    }

    /// Pins or unpins a shortcut on the Home tab. Returns false when the list is full.
    @discardableResult
    public func toggleFavorite(_ name: String) -> Bool {
        if let index = favoriteShortcuts.firstIndex(of: name) {
            favoriteShortcuts.remove(at: index)
            return true
        }
        guard favoriteShortcuts.count < Self.maximumFavoriteShortcuts else { return false }
        favoriteShortcuts.append(name)
        return true
    }

    /// Adds a shortcut beside Home, after the others. Home itself is always there.
    @discardableResult
    public func addFeatureShortcut(_ item: LauncherItem) -> Bool {
        var selection = FeatureShortcutSelection(items: featureShortcuts)
        guard selection.add(item) else { return false }
        featureShortcuts = selection.items
        return true
    }

    @discardableResult
    public func removeFeatureShortcut(_ item: LauncherItem) -> Bool {
        var selection = FeatureShortcutSelection(items: featureShortcuts)
        guard selection.remove(item) else { return false }
        featureShortcuts = selection.items
        return true
    }


    public func resetAppearance() {
        appearance = .standard
    }

    private enum Key {
        /// Settings from the floating pill style, removed in 1.3.3.
        static let retired = ["shape.style", "shape.verticalOffset", "shape.horizontalOffset"]
        static let pitchBlack = "shape.pitchBlack"
        static let size = "shape.size"
        static let nookLayout = "shape.nookLayout"
        static let width = "shape.width"
        static let height = "shape.height"
        static let showWhenIdle = "behavior.showWhenIdle"
        static let notchOpenMode = "behavior.notchOpenMode"
        static let hoverDelay = "behavior.hoverDelay"
        /// Legacy boolean retained only to migrate versions that shipped before interaction modes.
        static let expandOnHover = "behavior.expandOnHover"
        static let collapseOnPointerExit = "behavior.collapseOnPointerExit"
        static let haptics = "behavior.haptics"
        static let liquid = "behavior.liquidAnimations"
        static let menuBarIcon = "general.showMenuBarIcon"
        static let display = "general.display"
        static let timerSound = "timer.sound"
        static let nowPlaying = "activity.nowPlaying"
        static let lyrics = "activity.lyrics"
        static let timer = "activity.timer"
        static let calls = "activity.calls"
        static let airDrop = "activity.airDrop"
        static let charging = "alert.charging"
        static let lowBattery = "alert.lowBattery"
        static let headphones = "alert.headphones"
        static let linger = "nowPlaying.pausedLinger"
        static let welcome = "app.hasShownWelcome"
        static let tray = "home.tray"
        static let mirror = "home.mirror"
        static let clipboard = "home.clipboard"
        static let notes = "home.notes"
        static let downloads = "alert.downloads"
        static let reminders = "home.reminders"
        static let stats = "home.stats"
        static let lockScreen = "general.lockScreen"
        static let keyboardShortcuts = "general.keyboardShortcuts"
        static let checksForUpdates = "general.checksForUpdates"
        static let focusMinutes = "timer.focusMinutes"
        static let breakMinutes = "timer.breakMinutes"
        static let calendar = "home.calendar"
        static let shortcuts = "home.shortcuts"
        static let favoriteShortcuts = "home.favoriteShortcuts"
        static let featureShortcuts = "home.featureShortcuts"
        static let levels = "alert.levels"
    }
}
