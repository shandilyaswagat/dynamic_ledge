import Foundation
import Testing
@testable import NotchKit

@Suite("Lock Screen preferences")
struct LockScreenPreferencesTests {
    private let power = PowerSnapshot(hasBattery: true, level: 80, isOnAC: true, isCharging: true, isLowPowerMode: false)

    @Test func masterSwitchHidesEveryActivity() {
        #expect(LockScreenContent.choose(enabled: false, showMusic: true, showTimers: true, showCharging: true,
                                        timer: true, music: true, stopwatch: true, power: power) == nil)
    }

    @Test func onlyAllowedContentParticipatesInPriority() {
        #expect(LockScreenContent.choose(enabled: true, showMusic: true, showTimers: false, showCharging: true,
                                        timer: true, music: true, stopwatch: true, power: power) == .music)
        #expect(LockScreenContent.choose(enabled: true, showMusic: false, showTimers: false, showCharging: true,
                                        timer: true, music: true, stopwatch: true, power: power) == .charging(level: 80, isCharging: true))
        #expect(LockScreenContent.choose(enabled: true, showMusic: false, showTimers: false, showCharging: false,
                                        timer: true, music: true, stopwatch: true, power: power) == nil)
        #expect(LockScreenContent.choose(enabled: true, showMusic: false, showTimers: true, showCharging: false,
                                        timer: false, music: true, stopwatch: true, power: power) == .stopwatch)
    }

    @Test func artworkOnlyChangesMusicPresentation() {
        #expect(LockScreenContent.music.presentation(expandedArtwork: true) == .expanded(.nowPlaying))
        #expect(LockScreenContent.music.presentation(expandedArtwork: false) == .compact(primary: .nowPlaying, secondary: nil))
        #expect(LockScreenContent.timer.presentation(expandedArtwork: true) == LockScreenContent.timer.presentation)
    }

    @MainActor
    @Test func choicesPersistWithoutEnablingTheMasterSwitch() {
        let name = "LockScreenPreferences-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsStore(defaults: defaults)
        #expect(!settings.lockScreenEnabled)
        #expect(!settings.lockScreenArtworkEnabled)
        #expect(!settings.lockScreenLyricsEnabled)
        #expect(settings.lockScreenMusicEnabled && settings.lockScreenTimersEnabled && settings.lockScreenChargingEnabled)
        settings.lockScreenMusicEnabled = false
        settings.lockScreenTimersEnabled = false
        settings.lockScreenChargingEnabled = false
        settings.lockScreenArtworkEnabled = true
        settings.lockScreenLyricsEnabled = true
        settings.lockScreenEnabled = true
        settings.lockScreenEnabled = false
        let restored = SettingsStore(defaults: defaults)
        #expect(!restored.lockScreenEnabled)
        #expect(!restored.lockScreenMusicEnabled && !restored.lockScreenTimersEnabled && !restored.lockScreenChargingEnabled)
        #expect(restored.lockScreenArtworkEnabled)
        #expect(restored.lockScreenLyricsEnabled)
    }

    @MainActor
    @Test func olderEnabledInstallationsKeepTheirCompactAppearance() {
        let name = "LockScreenMigration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: "general.lockScreen")
        defaults.set("invalid", forKey: "lockScreen.artwork")
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.lockScreenEnabled)
        #expect(settings.lockScreenMusicEnabled && settings.lockScreenTimersEnabled && settings.lockScreenChargingEnabled)
        #expect(!settings.lockScreenArtworkEnabled)
    }
}
