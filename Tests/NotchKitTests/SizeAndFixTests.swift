import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import NotchKit

@Suite("Size modes")
struct SizeModeTests {
    let screen = ScreenMetrics.sample

    private func engine(_ size: NotchSize, screen: ScreenMetrics = .sample) -> LayoutEngine {
        var appearance = NotchAppearance.standard
        appearance.size = size
        return LayoutEngine(screen: screen, appearance: appearance)
    }

    @Test func largeIsTheOriginalDesign() {
        #expect(NotchAppearance.standard.size == .large)
        let large = engine(.large)
        #expect(large.scale == 1)
        #expect(large.compactBodyWidth == CGFloat(180 + 2 * 47))
        #expect(large.expandedWidth == CGFloat(390))
        #expect(large.expandedContentHeight(for: .expanded(.nowPlaying), homeHasMedia: false) == IslandMetrics.ContentHeight.nowPlaying)
    }

    @Test func smallerSizesShrinkEverything() {
        let presentations: [IslandPresentation] = [
            .compact(primary: .timer, secondary: .nowPlaying), .expanded(.nowPlaying), .expanded(.timer), .home,
            .alert(.charging(level: 50, isCharging: true)), .alert(.timerFinished), .drop(targeted: false),
        ]
        let external = ScreenMetrics(size: CGSize(width: 1920, height: 1080), notch: nil, menuBarHeight: 25)
        for screen in [ScreenMetrics.sample, external] {
            for presentation in presentations {
                let sizes = [NotchSize.small, .medium, .large].map {
                    engine($0, screen: screen).layout(for: presentation, homeHasMedia: true, hovering: false)
                }
                #expect(sizes[0].pill.width <= sizes[1].pill.width && sizes[1].pill.width <= sizes[2].pill.width, "\(presentation)")
                #expect(sizes[0].pill.height <= sizes[1].pill.height && sizes[1].pill.height <= sizes[2].pill.height, "\(presentation)")
                #expect(sizes.map(\.contentScale) == [0.8, 0.9, 1])
            }
        }
    }

    @Test func notchCompactStaysAtLeastNotchHeightAndClearsTheCamera() throws {
        let notch = try #require(screen.notch)
        let small = engine(.small).layout(for: .compact(primary: .timer, secondary: nil), homeHasMedia: false, hovering: false)
        #expect(small.pill.height == notch.height)
        #expect(small.cameraGap == notch.width)
        #expect(small.content.width - notch.width >= 2 * 30, "ears still hold an icon and a countdown")
    }

    @Test func smallExpandedStillFitsItsContent() {
        let small = engine(.small)
        #expect(small.expandedWidth >= small.compactBodyWidth + 40)
        let height = small.expandedContentHeight(for: .expanded(.nowPlaying), homeHasMedia: false)
        #expect(height == (IslandMetrics.ContentHeight.nowPlaying * 0.8).rounded())
    }

    @MainActor
    @Test func sizePersists() {
        let name = "SizeModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        store.appearance.size = .small
        #expect(SettingsStore(defaults: defaults).appearance.size == .small)
        defaults.set("gigantic", forKey: "shape.size")
        #expect(SettingsStore(defaults: defaults).appearance.size == .large, "unknown values fall back to Large")
    }
}

@Suite("Window")
struct WindowTests {
    @Test func windowIsFixedForADisplay() {
        let screen = ScreenMetrics.sample
        var sizes = Set<CGSize.Hashable>()
        for size in NotchSize.allCases {
            for width in [120.0, 200, 420] {
                for height in [24.0, 32, 52] {
                    var appearance = NotchAppearance.standard
                    appearance.size = size
                    appearance.width = width
                    appearance.height = height
                    let engine = LayoutEngine(screen: screen, appearance: appearance)
                    sizes.insert(CGSize.Hashable(engine.windowSize))
                    #expect(engine.windowOriginX == 0)
                }
            }
        }
        #expect(sizes.count == 1, "settings never move or resize the window")
        #expect(sizes.first?.width == screen.size.width)
    }
}

private extension CGSize {
    struct Hashable: Swift.Hashable {
        let width: CGFloat
        let height: CGFloat
        init(_ size: CGSize) {
            width = size.width
            height = size.height
        }
    }
}

@Suite("Media helper reader")
struct BridgeReaderTests {
    @Test func reassemblesLinesSplitAcrossReads() {
        let reader = BridgeLineReader()
        let line = #"{"type":"nowPlaying","hasInfo":true,"title":"Song","playing":true}"# + "\n"
        let bytes = Array(line.utf8)
        let first = reader.consume(Data(bytes[0..<20]))
        #expect(first.isEmpty)
        let second = reader.consume(Data(bytes[20...]) + Data(#"{"type":"ready"}"#.utf8) + Data("\n".utf8))
        #expect(second.count == 2)
        if case .nowPlaying(let info?, _) = second.first?.message {
            #expect(info.title == "Song")
        } else {
            Issue.record("expected now playing")
        }
        #expect(second.last?.message == .ready)
    }

    @Test func skipsGarbageAndEmptyLines() {
        let reader = BridgeLineReader()
        let messages = reader.consume(Data("\n\nnot json\n{\"type\":\"ready\"}\n".utf8))
        #expect(messages.map(\.message) == [.ready])
    }

    @Test func artworkTintIsWorkedOutOffTheMainThread() throws {
        let png = try #require(Self.solidPNG(red: 1, green: 0, blue: 0))
        let line = #"{"type":"nowPlaying","hasInfo":true,"title":"T","artworkKey":"k","artwork":""# + png.base64EncodedString() + "\"}\n"
        let messages = BridgeLineReader().consume(Data(line.utf8))
        let accent = try #require(messages.first?.artworkAccent)
        #expect(accent.red > 0.9 && accent.green < 0.5)
    }

    @Test func runawayOutputIsDropped() {
        let reader = BridgeLineReader()
        _ = reader.consume(Data(repeating: 0x41, count: BridgeLineReader.maximumBuffer + 1))
        let messages = reader.consume(Data("\n{\"type\":\"ready\"}\n".utf8))
        #expect(messages.map(\.message) == [.ready], "buffer was reset, so the next line parses")
    }

    static func solidPNG(red: CGFloat, green: CGFloat, blue: CGFloat) -> Data? {
        guard let context = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

@MainActor
@Suite("Now Playing state")
struct NowPlayingStateTests {
    private func playing(_ isPlaying: Bool, elapsed: Double = 10, at date: Date) -> NowPlayingInfo {
        NowPlayingInfo(title: "Song", artist: "A", duration: 200, elapsed: elapsed, sampledAt: date, playbackRate: isPlaying ? 1 : 0, isPlaying: isPlaying)
    }

    @Test func staleReportDoesNotFlipPlayPauseBack() {
        let service = NowPlayingService()
        let start = Date()
        service.apply(playing(true, at: start), artworkData: nil)
        service.togglePlayPause()
        #expect(service.info?.isPlaying == false)
        // A report sent before the player reacted.
        service.apply(playing(true, at: start), artworkData: nil, now: start.addingTimeInterval(0.3))
        #expect(service.info?.isPlaying == false, "local state kept")
        // The player catches up.
        service.apply(playing(false, elapsed: 11, at: start), artworkData: nil, now: start.addingTimeInterval(0.6))
        #expect(service.info?.isPlaying == false)
        #expect(service.info?.elapsed == 11)
        // Later reports are trusted again.
        service.apply(playing(true, at: start), artworkData: nil, now: start.addingTimeInterval(5))
        #expect(service.info?.isPlaying == true)
    }

    @Test func expectationExpires() {
        let service = NowPlayingService()
        let start = Date()
        service.apply(playing(true, at: start), artworkData: nil)
        service.togglePlayPause()
        service.apply(playing(true, at: start), artworkData: nil, now: start.addingTimeInterval(2))
        #expect(service.info?.isPlaying == true, "player ignored the command; show the truth")
    }

    @Test func pausingLingersThenNothingPlaying() {
        let service = NowPlayingService()
        let start = Date()
        service.apply(playing(true, at: start), artworkData: nil)
        #expect(service.isActivityVisible)
        service.apply(playing(false, at: start), artworkData: nil)
        #expect(service.isLingering)
        #expect(service.isActivityVisible)
        service.apply(nil, artworkData: nil)
        #expect(!service.isActivityVisible)
        #expect(service.artwork == nil)
    }

    @Test func artworkBelongsToItsTrack() throws {
        let service = NowPlayingService()
        let png = try #require(BridgeReaderTests.solidPNG(red: 0, green: 0, blue: 1))
        var info = playing(true, at: Date())
        info.artworkKey = "a"
        service.apply(info, artworkData: png, accent: ColorMath.RGB(red: 0, green: 0, blue: 1))
        #expect(service.artwork != nil)
        #expect(service.accent.blue == 1)
        service.apply(info, artworkData: nil)
        #expect(service.artwork != nil, "same track keeps its art")
        info.title = "Next"
        info.artworkKey = nil
        service.apply(info, artworkData: nil)
        #expect(service.artwork == nil, "new track without art clears the old art")
        #expect(service.accent == .white)
    }
}

@MainActor
@Suite("Model fixes")
struct ModelFixTests {
    private func makeModel() -> IslandModel {
        let name = "ModelFixTests.\(UUID().uuidString)"
        let model = IslandModel(settings: SettingsStore(defaults: UserDefaults(suiteName: name)!), tray: TrayStore(folder: nil))
        model.screen = .sample
        return model
    }

    @Test func timerDoneInterruptsAnotherAlert() {
        let model = makeModel()
        model.receive(.charging(level: 40, isCharging: true))
        #expect(model.presentation == .alert(.charging(level: 40, isCharging: true)))
        model.receive(.timerFinished)
        #expect(model.presentation == .alert(.timerFinished))
        model.stopTimerAlarm()
        #expect(model.presentation == .alert(.charging(level: 40, isCharging: true)), "the interrupted alert comes back")
    }

    @Test func welcomeIsShownOnce() {
        let name = "ModelFixTests.welcome.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = SettingsStore(defaults: defaults)
        #expect(!store.hasShownWelcome)
        store.hasShownWelcome = true
        #expect(SettingsStore(defaults: defaults).hasShownWelcome)
    }

    @Test func clickingAnAlertDismissesItButNotTimerDone() {
        let model = makeModel()
        model.receive(.welcome)
        model.tapPill()
        #expect(model.presentation == .hidden(peek: false))
        model.receive(.timerFinished)
        model.tapPill()
        #expect(model.presentation == .alert(.timerFinished), "needs Stop or Repeat")
    }

    @Test func sizeChangesTheLiveLayout() {
        let model = makeModel()
        model.startTimer(60)
        let large = model.layout.pill.width
        model.settings.appearance.size = .small
        #expect(model.layout.pill.width < large)
        #expect(model.layout.contentScale == 0.8)
    }
}

@Suite("Downloaded app")
struct QuarantineTests {
    @Test func helperCopyHasNoQuarantineFlagAndSameBytes() throws {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let original = temp.appendingPathComponent("original.dylib")
        try Data("library bytes".utf8).write(to: original)
        let flag = "0081;00000000;Safari;"
        setxattr(original.path, "com.apple.quarantine", flag, flag.utf8.count, 0, 0)
        #expect(getxattr(original.path, "com.apple.quarantine", nil, 0, 0, 0) > 0)

        let copy = try #require(MediaBridgeClient.unquarantinedCopy(of: original, in: temp.appendingPathComponent("support")))
        #expect(getxattr(copy.path, "com.apple.quarantine", nil, 0, 0, 0) < 0, "no quarantine flag")
        #expect(try Data(contentsOf: copy) == Data("library bytes".utf8))

        // An updated app replaces the copy; an unchanged one reuses it.
        try Data("new bytes".utf8).write(to: original)
        let again = try #require(MediaBridgeClient.unquarantinedCopy(of: original, in: temp.appendingPathComponent("support")))
        #expect(try Data(contentsOf: again) == Data("new bytes".utf8))
    }
}
