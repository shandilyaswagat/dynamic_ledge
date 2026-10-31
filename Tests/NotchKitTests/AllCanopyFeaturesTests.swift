import AppKit
import CoreAudio
import Foundation
import Testing
@testable import NotchKit

@MainActor
@Suite("All Canopy reference features end-to-end")
struct AllCanopyFeaturesTests {
    // MARK: 1. Synchronized Lyrics
    @Test func lrcParserHandlesComplexCasesAndTiming() {
        let lrc = """
        [ti:Reference Song]
        [ar:Reference Artist]
        [al:Reference Album]
        [by:Creator]
        [offset:0]
        [00:01.00]Intro line
        [00:05.250]Verse one
        [00:10.00][00:20.00]Chorus line repeated
        [00:15.50]
        [01:00.00]Outro
        """
        let parsed = LRCParser.parse(synced: lrc, plain: "Plain fallback")
        #expect(parsed.isSynced)
        #expect(parsed.lines.count == 6)

        // Verify sorted order
        #expect(parsed.lines[0].time == 1.0)
        #expect(parsed.lines[0].text == "Intro line")
        #expect(parsed.lines[1].time == 5.25)
        #expect(parsed.lines[1].text == "Verse one")
        #expect(parsed.lines[2].time == 10.0)
        #expect(parsed.lines[2].text == "Chorus line repeated")
        #expect(parsed.lines[3].time == 15.5)
        #expect(parsed.lines[3].text == "")
        #expect(parsed.lines[4].time == 20.0)
        #expect(parsed.lines[4].text == "Chorus line repeated")
        #expect(parsed.lines[5].time == 60.0)
        #expect(parsed.lines[5].text == "Outro")

        // Boundary checks
        #expect(parsed.activeIndex(at: 0.0) == nil)
        #expect(parsed.activeIndex(at: 0.99) == nil)
        #expect(parsed.activeIndex(at: 1.0) == 0)
        #expect(parsed.activeIndex(at: 3.0) == 0)
        #expect(parsed.activeIndex(at: 5.25) == 1)
        #expect(parsed.activeIndex(at: 9.99) == 1)
        #expect(parsed.activeIndex(at: 10.0) == 2)
        #expect(parsed.activeIndex(at: 20.0) == 4)
        #expect(parsed.activeIndex(at: 99.0) == 5)

        #expect(parsed.activeLine(at: 5.25)?.text == "Verse one")
    }

    // MARK: 2. Audio Output Picker
    @Test func audioOutputPickerDeviceSelectionAndSymbols() {
        let speaker = AudioOutputDevice(id: 10, name: "MacBook Pro Speakers", isDefault: true, isBluetooth: false)
        let airPods = AudioOutputDevice(id: 20, name: "AirPods Max", isDefault: false, isBluetooth: true)
        let studioDisplay = AudioOutputDevice(id: 30, name: "Studio Display", isDefault: false, isBluetooth: false)

        #expect(speaker.symbol == "speaker.wave.2.fill")
        #expect(airPods.symbol == "airpodsmax")
        #expect(studioDisplay.symbol == "speaker.wave.2.fill")

        var switchedTo: AudioDeviceID?
        var currentDefault: AudioDeviceID = 10
        let service = AudioOutputService(
            listProvider: {
                [
                    AudioOutputDevice(id: 10, name: "MacBook Pro Speakers", isDefault: currentDefault == 10, isBluetooth: false),
                    AudioOutputDevice(id: 20, name: "AirPods Max", isDefault: currentDefault == 20, isBluetooth: true)
                ]
            },
            setter: { id in
                switchedTo = id
                currentDefault = id
                return true
            }
        )

        #expect(service.currentDevice?.id == 10)
        let success = service.selectDevice(airPods)
        #expect(success)
        #expect(switchedTo == 20)
        #expect(service.currentDevice?.id == 20)
    }

    // MARK: 3. Tray File Conversion & Preservation
    @Test func fileConverterConvertsAndGuaranteesOriginalIntegrity() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create test 16x16 PNG image
        let img = NSImage(size: NSSize(width: 16, height: 16))
        img.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        img.unlockFocus()
        let tiffData = img.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiffData)!
        let pngData = rep.representation(using: .png, properties: [:])!

        let sourceURL = tempDir.appendingPathComponent("image.png")
        try pngData.write(to: sourceURL)
        let originalBytes = try Data(contentsOf: sourceURL)

        // Test non-convertible files
        #expect(!FileConverter.isConvertible(url: URL(fileURLWithPath: "/tmp/test.mp3")))
        #expect(FileConverter.isConvertible(url: sourceURL))

        // Convert to JPEG
        let outDir = tempDir.appendingPathComponent("exports")
        let jpegURL = try FileConverter.convertImage(at: sourceURL, to: .jpeg, destinationFolder: outDir)
        #expect(FileManager.default.fileExists(atPath: jpegURL.path))
        #expect(jpegURL.pathExtension.lowercased() == "jpg")

        // Convert to TIFF
        let tiffURL = try FileConverter.convertImage(at: sourceURL, to: .tiff, destinationFolder: outDir)
        #expect(FileManager.default.fileExists(atPath: tiffURL.path))

        // STRICT PRESERVATION CHECK: source file must exist and be 100% byte-for-byte identical
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
        let afterBytes = try Data(contentsOf: sourceURL)
        #expect(afterBytes == originalBytes)
    }

    // MARK: 4. Window Behavior: Fullscreen, Capture Exclusion, HUD
    @Test func windowCaptureExclusionAndFullscreenSettings() {
        let panel = IslandPanel(hideFromCapture: false, hideInFullscreen: false)
        #expect(panel.sharingType == .readOnly)
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))

        panel.applyCaptureExclusion(true)
        #expect(panel.sharingType == .none)

        panel.applyFullscreenHiding(true)
        #expect(!panel.collectionBehavior.contains(.fullScreenAuxiliary))

        let defaults = UserDefaults(suiteName: "WindowSettings-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        let settings = SettingsStore(defaults: defaults)

        #expect(!settings.hideInFullscreen)
        #expect(!settings.hideFromScreenCapture)
        #expect(!settings.suppressHUD)

        settings.hideInFullscreen = true
        settings.hideFromScreenCapture = true
        settings.suppressHUD = true

        let restored = SettingsStore(defaults: defaults)
        #expect(restored.hideInFullscreen)
        #expect(restored.hideFromScreenCapture)
        #expect(restored.suppressHUD)
    }

    // MARK: 5. Focus Notifications
    @Test func focusNotificationLifecycleAndFilter() {
        let monitor = FocusMonitor()
        var emitted: IslandAlert?
        monitor.onAlert = { emitted = $0 }

        monitor.notify(mode: FocusMode(id: "work", name: "Work", symbol: "briefcase.fill"))
        #expect(emitted == .focus(name: "Work", symbol: "briefcase.fill"))
        #expect(emitted?.kind == .focus)

        // Subsequent notification of the same mode does not duplicate
        emitted = nil
        monitor.notify(mode: FocusMode(id: "work", name: "Work", symbol: "briefcase.fill"))
        #expect(emitted == nil)

        // Switching mode announces new focus
        monitor.notify(mode: .dnd)
        #expect(emitted == .focus(name: "Do Not Disturb", symbol: "moon.fill"))
    }

    // MARK: 6. AirPods Battery & Listening Modes
    @Test func airPodsBatteryAndListeningModeAlert() {
        let battery = AirPodsBatteryStatus(left: 75, right: 80, caseBattery: 95)
        let alert = IslandAlert.airPods(
            name: "AirPods Pro",
            symbol: "airpodspro",
            battery: battery,
            mode: .transparency
        )
        #expect(alert.kind == .headphones)
        #expect(alert.displayDuration == 4)

        #expect(AirPodsListeningMode.allCases.count == 3)
        #expect(AirPodsListeningMode.off.symbol == "headphones")
        #expect(AirPodsListeningMode.transparency.symbol == "ambient.light")
        #expect(AirPodsListeningMode.noiseCancellation.symbol == "ear.and.waveform")
    }

    // MARK: 7. Online Artwork
    @Test func onlineArtworkSearchURLAndHighResConversion() {
        let info = NowPlayingInfo(title: "Song", artist: "Artist", album: "Album")
        let url = OnlineRequests.artwork(info)!
        #expect(url.host == "itunes.apple.com")
        #expect(url.path == "/search")

        let lowRes = "https://is1-ssl.mzstatic.com/image/thumb/Music/v4/100x100bb.jpg"
        let highRes = OnlineRequests.highResolutionArtworkURL(from: lowRes)!
        #expect(highRes.absoluteString.contains("600x600bb.jpg"))
    }

    // MARK: 8. Lock-Screen Aurora, Clock & Glass Art
    @Test func lockScreenCustomizationPreferences() {
        let defaults = UserDefaults(suiteName: "LockScreenCustomization-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        let settings = SettingsStore(defaults: defaults)

        #expect(!settings.lockScreenAuroraEnabled)
        #expect(!settings.lockScreenGlassArtEnabled)
        #expect(!settings.lockScreenClockEnabled)
        #expect(!settings.lockScreenClockFormat24H)

        settings.lockScreenAuroraEnabled = true
        settings.lockScreenGlassArtEnabled = true
        settings.lockScreenClockEnabled = true
        settings.lockScreenClockFormat24H = true

        let reloaded = SettingsStore(defaults: defaults)
        #expect(reloaded.lockScreenAuroraEnabled)
        #expect(reloaded.lockScreenGlassArtEnabled)
        #expect(reloaded.lockScreenClockEnabled)
        #expect(reloaded.lockScreenClockFormat24H)
    }

    // MARK: 9. Audio-Reactive Spectrum
    @Test func fftProcessorAccurateFrequencyBandPeaks() {
        let sampleRate = 44100.0
        let n = 512

        // Test 1: Sub-bass 60 Hz tone
        var subBassSamples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            subBassSamples[i] = Float(sin(2.0 * .pi * 60.0 * t))
        }
        let subBassBands = FFTProcessor.computeBands(samples: subBassSamples, sampleRate: sampleRate)
        #expect(subBassBands[0] > subBassBands[4])

        // Test 2: Midrange 1000 Hz tone
        var midSamples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            midSamples[i] = Float(sin(2.0 * .pi * 1000.0 * t))
        }
        let midBands = FFTProcessor.computeBands(samples: midSamples, sampleRate: sampleRate)
        #expect(midBands[2] > midBands[0])
        #expect(midBands[2] > midBands[4])

        // Test 3: High Treble 10000 Hz tone
        var trebleSamples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / sampleRate
            trebleSamples[i] = Float(sin(2.0 * .pi * 10000.0 * t))
        }
        let trebleBands = FFTProcessor.computeBands(samples: trebleSamples, sampleRate: sampleRate)
        #expect(trebleBands[4] > trebleBands[0])
    }

    // MARK: 10. Per-App EQ
    @Test func perAppEQPresetsAndFilteringStability() {
        for preset in EQPreset.allCases {
            #expect(preset.bandGains.count == 10)
        }

        // Test filter stability: no NaN or Inf for full range
        for freq in AudioDSP.bandCenterFrequencies {
            let coeffs = AudioDSP.peakingFilter(frequency: freq, gainDB: 6.0, q: 1.414, sampleRate: 44100)
            #expect(!coeffs.b0.isNaN && !coeffs.b0.isInfinite)
            #expect(!coeffs.a1.isNaN && !coeffs.a1.isInfinite)

            let input = [1.0, -1.0, 0.5, -0.5, 0.25, 0.0]
            let output = AudioDSP.process(samples: input, coefficients: coeffs)
            #expect(output.allSatisfy { !$0.isNaN && !$0.isInfinite })
        }

        let engine = PerAppEQEngine()
        let spotifyProfile = EQProfile(bundleIdentifier: "com.spotify.client", gains: EQPreset.rock.bandGains)
        engine.setProfile(spotifyProfile)

        engine.activateApp(bundleIdentifier: "com.spotify.client")
        #expect(engine.activeProfile()?.gains == EQPreset.rock.bandGains)

        engine.globalBypass = true
        #expect(engine.activeProfile() == nil)

        engine.resetAndRecover()
        #expect(!engine.globalBypass)
    }
}
