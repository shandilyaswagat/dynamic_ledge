import Foundation
import Testing
@testable import NotchKit

@Suite("Alert queue")
struct AlertQueueTests {
    let start = Date(timeIntervalSince1970: 1_000)

    @Test func showsOneAtATimeInOrder() {
        var queue = AlertQueue()
        queue.enqueue(.charging(level: 50, isCharging: true), now: start)
        queue.enqueue(.headphones(name: "AirPods", symbol: "airpods"), now: start)
        #expect(queue.current == nil)
        let result1 = queue.promote(now: start, allowNonUrgent: true)
        #expect(result1)
        #expect(queue.current == .charging(level: 50, isCharging: true))
        let result2 = queue.promote(now: start, allowNonUrgent: true)
        #expect(!result2, "only one at a time")
        #expect(queue.expiry == start.addingTimeInterval(3))
        let result3 = queue.expire(now: start.addingTimeInterval(2.9))
        #expect(!result3)
        let result4 = queue.expire(now: start.addingTimeInterval(3))
        #expect(result4)
        let result5 = queue.promote(now: start.addingTimeInterval(3), allowNonUrgent: true)
        #expect(result5)
        #expect(queue.current?.kind == .headphones)
    }

    @Test func sameKindReplaces() {
        var queue = AlertQueue()
        queue.enqueue(.lowBattery(level: 20), now: start)
        queue.enqueue(.charging(level: 19, isCharging: true), now: start)
        #expect(queue.pending == [.charging(level: 19, isCharging: true)])
        queue.promote(now: start, allowNonUrgent: true)
        let later = start.addingTimeInterval(2)
        let result6 = queue.enqueue(.charging(level: 20, isCharging: true), now: later)
        #expect(result6, "visible alert updated in place")
        #expect(queue.current == .charging(level: 20, isCharging: true))
        #expect(queue.expiry == later.addingTimeInterval(3), "timer restarts")
    }

    @Test func nonUrgentWaitsWhileExpanded() {
        var queue = AlertQueue()
        queue.enqueue(.charging(level: 50, isCharging: true), now: start)
        queue.enqueue(.timerFinished, now: start)
        let result7 = queue.promote(now: start, allowNonUrgent: false)
        #expect(result7)
        #expect(queue.current == .timerFinished)
        #expect(queue.expiry == start.addingTimeInterval(600), "timer alert waits for the user, up to ten minutes")
        queue.dismissCurrent()
        let result8 = queue.promote(now: start, allowNonUrgent: false)
        #expect(!result8)
        let result9 = queue.promote(now: start, allowNonUrgent: true)
        #expect(result9)
    }

    @Test func urgentAlertTakesOverAndTheOtherWaits() {
        var queue = AlertQueue()
        queue.enqueue(.charging(level: 50, isCharging: true), now: start)
        queue.promote(now: start, allowNonUrgent: true)
        let later = start.addingTimeInterval(1)
        let changed = queue.enqueue(.timerFinished, now: later)
        #expect(changed)
        #expect(queue.current == .timerFinished)
        #expect(queue.pending.first == .charging(level: 50, isCharging: true), "interrupted alert goes back to the front")
        queue.dismissCurrent()
        let promoted = queue.promote(now: later, allowNonUrgent: true)
        #expect(promoted)
        #expect(queue.current == .charging(level: 50, isCharging: true))
    }

    @Test func urgentDoesNotDisplaceUrgent() {
        var queue = AlertQueue()
        queue.enqueue(.timerFinished, now: start)
        queue.promote(now: start, allowNonUrgent: true)
        queue.enqueue(.welcome, now: start)
        #expect(queue.current == .timerFinished)
        #expect(queue.pending == [.welcome])
    }

    @Test func removeAllOfKind() {
        var queue = AlertQueue()
        queue.enqueue(.timerFinished, now: start)
        queue.promote(now: start, allowNonUrgent: true)
        queue.enqueue(.lowBattery(level: 10), now: start)
        queue.removeAll(of: .timer)
        #expect(queue.current == nil)
        #expect(queue.pending == [.lowBattery(level: 10)])
    }
}

@Suite("Countdown timer")
struct CountdownTimerTests {
    let start = Date(timeIntervalSince1970: 5_000)

    @Test func runsDown() {
        let timer = CountdownTimer(duration: 300, now: start)
        #expect(timer.remaining(at: start.addingTimeInterval(60)) == 240)
        #expect(timer.progress(at: start.addingTimeInterval(150)) == 0.5)
        #expect(timer.remaining(at: start.addingTimeInterval(999)) == 0)
    }

    @Test func pauseAndResumeKeepRemainingTime() {
        var timer = CountdownTimer(duration: 300, now: start)
        timer.pause(now: start.addingTimeInterval(100))
        #expect(timer.isPaused)
        #expect(timer.remaining(at: start.addingTimeInterval(1_000)) == 200)
        timer.resume(now: start.addingTimeInterval(1_000))
        #expect(timer.remaining(at: start.addingTimeInterval(1_050)) == 150)
        let result10 = timer.finishIfDue(now: start.addingTimeInterval(1_100))
        #expect(!result10)
        let result11 = timer.finishIfDue(now: start.addingTimeInterval(1_200))
        #expect(result11)
        #expect(timer.isFinished)
    }

    @Test func addTime() {
        var timer = CountdownTimer(duration: 60, now: start)
        timer.add(60, now: start.addingTimeInterval(30))
        #expect(timer.remaining(at: start.addingTimeInterval(30)) == 90)
        #expect(timer.duration == 120)
        timer.pause(now: start.addingTimeInterval(30))
        timer.add(-200, now: start.addingTimeInterval(30))
        #expect(timer.remaining(at: start) == 0)
    }

    @Test func clampsDuration() {
        #expect(CountdownTimer(duration: -5, now: start).duration == CountdownTimer.minimumDuration)
        #expect(CountdownTimer(duration: 1e9, now: start).duration == CountdownTimer.maximumDuration)
    }

    @Test func pauseIsIgnoredWhenNotRunning() {
        var timer = CountdownTimer(duration: 10, now: start)
        timer.finishIfDue(now: start.addingTimeInterval(10))
        timer.pause(now: start)
        timer.resume(now: start)
        #expect(timer.isFinished)
        #expect(timer.endDate == nil)
    }
}

@Suite("Battery alerts")
struct PowerTransitionTests {
    func snapshot(_ level: Int, ac: Bool, charging: Bool = false, battery: Bool = true) -> PowerSnapshot {
        PowerSnapshot(hasBattery: battery, level: level, isOnAC: ac, isCharging: charging, isLowPowerMode: false)
    }

    @Test func noAlertOnLaunch() {
        #expect(PowerTransitions.alert(from: nil, to: snapshot(5, ac: false)) == nil)
    }

    @Test func pluggingInShowsCharging() {
        #expect(PowerTransitions.alert(from: snapshot(40, ac: false), to: snapshot(40, ac: true, charging: true)) == .charging(level: 40, isCharging: true))
        #expect(PowerTransitions.alert(from: snapshot(80, ac: false), to: snapshot(80, ac: true, charging: false)) == .charging(level: 80, isCharging: false))
        #expect(PowerTransitions.alert(from: snapshot(40, ac: true), to: snapshot(41, ac: true, charging: true)) == nil)
    }

    @Test func lowBatteryAtThresholdsOnly() {
        #expect(PowerTransitions.alert(from: snapshot(21, ac: false), to: snapshot(20, ac: false)) == .lowBattery(level: 20))
        #expect(PowerTransitions.alert(from: snapshot(20, ac: false), to: snapshot(19, ac: false)) == nil)
        #expect(PowerTransitions.alert(from: snapshot(11, ac: false), to: snapshot(10, ac: false)) == .lowBattery(level: 10))
        #expect(PowerTransitions.alert(from: snapshot(25, ac: false), to: snapshot(8, ac: false)) == .lowBattery(level: 8))
        #expect(PowerTransitions.alert(from: snapshot(21, ac: true), to: snapshot(20, ac: true)) == nil)
    }

    @Test func desktopsNeverAlert() {
        #expect(PowerTransitions.alert(from: snapshot(100, ac: false, battery: false), to: snapshot(100, ac: true, battery: false)) == nil)
    }

    @Test func levelIsClamped() {
        #expect(snapshot(140, ac: true).level == 100)
        #expect(snapshot(-3, ac: true).level == 0)
    }
}

@Suite("Time formatting")
struct TimeFormattingTests {
    @Test func clock() {
        #expect(TimeFormatting.clock(0) == "0:00")
        #expect(TimeFormatting.clock(42.9) == "0:42")
        #expect(TimeFormatting.clock(42.1, roundingUp: true) == "0:43")
        #expect(TimeFormatting.clock(299.5, roundingUp: true) == "5:00")
        #expect(TimeFormatting.clock(3723) == "1:02:03")
        #expect(TimeFormatting.clock(-5) == "0:00")
        #expect(TimeFormatting.clock(.nan) == "0:00")
        #expect(TimeFormatting.clock(.infinity) == "0:00")
    }

    @Test func remaining() {
        #expect(TimeFormatting.remaining(elapsed: 19, duration: 200) == "-3:01")
        #expect(TimeFormatting.remaining(elapsed: 300, duration: 200) == "-0:00")
    }

    @Test func presets() {
        #expect(TimeFormatting.presetLabel(seconds: 60) == "1 min")
        #expect(TimeFormatting.presetLabel(seconds: 1800) == "30 min")
        #expect(TimeFormatting.presetLabel(seconds: 3600) == "1 hr")
        #expect(TimeFormatting.presetLabel(seconds: 5400) == "1 hr 30 min")
    }
}

@Suite("Now Playing data")
struct NowPlayingTests {
    @Test func parsesHelperOutput() throws {
        let line = #"{"type":"nowPlaying","hasInfo":true,"title":"Song","artist":"Band","album":"LP","duration":200,"elapsed":12,"rate":1,"timestamp":1000,"playing":true,"pid":42,"bundleID":"com.apple.Music","artworkKey":"k1","artwork":"AAEC"}"#
        let message = try #require(BridgeMessage.parse(Data(line.utf8)))
        guard case .nowPlaying(let info?, let artwork) = message else {
            Issue.record("expected info")
            return
        }
        #expect(info.title == "Song")
        #expect(info.artist == "Band")
        #expect(info.duration == 200)
        #expect(info.elapsed == 12)
        #expect(info.sampledAt == Date(timeIntervalSince1970: 1000))
        #expect(info.isPlaying)
        #expect(info.processIdentifier == 42)
        #expect(info.bundleIdentifier == "com.apple.Music")
        #expect(info.artworkKey == "k1")
        #expect(artwork == Data([0, 1, 2]))
    }

    @Test func emptyOrInvalidInfoMeansNothingPlaying() {
        #expect(BridgeMessage.parse(Data(#"{"type":"nowPlaying","hasInfo":false}"#.utf8)) == .nowPlaying(info: nil, artwork: nil))
        #expect(BridgeMessage.parse(Data(#"{"type":"nowPlaying","hasInfo":true,"title":"","artist":""}"#.utf8)) == .nowPlaying(info: nil, artwork: nil))
        #expect(BridgeMessage.parse(Data("not json".utf8)) == nil)
        #expect(BridgeMessage.parse(Data(#"{"type":"mystery"}"#.utf8)) == nil)
        #expect(BridgeMessage.parse(Data(#"{"type":"ready"}"#.utf8)) == .ready)
        #expect(BridgeMessage.parse(Data(#"{"type":"error","message":"x"}"#.utf8)) == .error("x"))
    }

    @Test func boundsUntrustedArtworkAndMetadata() throws {
        let text = String(repeating: "x", count: BridgeMessage.maximumTextLength + 100)
        let oversizedArtwork = Data(repeating: 0, count: BridgeMessage.maximumArtworkBytes + 1).base64EncodedString()
        let line = #"{"type":"nowPlaying","hasInfo":true,"title":"# + text + #"","artist":"Artist","artwork":"# + oversizedArtwork + #"}"#
        guard case .nowPlaying(let info?, let artwork) = try #require(BridgeMessage.parse(Data(line.utf8))) else {
            Issue.record("expected now playing data")
            return
        }
        #expect(info.title.count == BridgeMessage.maximumTextLength)
        #expect(artwork == nil)
    }

    @Test func badNumbersAreDropped() throws {
        let line = #"{"type":"nowPlaying","hasInfo":true,"title":"Live","duration":-1,"elapsed":-4,"timestamp":0,"pid":0,"bundleID":""}"#
        guard case .nowPlaying(let info?, _) = try #require(BridgeMessage.parse(Data(line.utf8))) else {
            Issue.record("expected info")
            return
        }
        #expect(info.duration == nil)
        #expect(info.elapsed == nil)
        #expect(info.sampledAt == nil)
        #expect(info.processIdentifier == nil)
        #expect(info.bundleIdentifier == nil)
        #expect(info.progress(at: Date()) == nil)
    }

    @Test func extrapolatesPositionWhilePlaying() {
        let sampled = Date(timeIntervalSince1970: 100)
        var info = NowPlayingInfo(title: "T", duration: 200, elapsed: 50, sampledAt: sampled, playbackRate: 1, isPlaying: true)
        #expect(info.elapsed(at: sampled.addingTimeInterval(10)) == 60)
        #expect(info.elapsed(at: sampled.addingTimeInterval(1_000)) == 200, "never past the end")
        #expect(info.elapsed(at: sampled.addingTimeInterval(-10)) == 50, "clock skew doesn't rewind")
        info.playbackRate = 2
        #expect(info.elapsed(at: sampled.addingTimeInterval(10)) == 70)
        info.isPlaying = false
        #expect(info.elapsed(at: sampled.addingTimeInterval(10)) == 50)
        #expect(info.progress(at: sampled) == 0.25)
    }
}

@Suite("Classifiers and maths")
struct ClassifierTests {
    @Test func callApps() {
        #expect(CallClassifier.isCallApp("us.zoom.xos"))
        #expect(CallClassifier.isCallApp("com.apple.FaceTime"))
        #expect(!CallClassifier.isCallApp("com.apple.VoiceMemos"))
        #expect(!CallClassifier.isCallApp(nil))
    }

    @Test func ignoredSystemServices() {
        #expect(CallClassifier.shouldIgnore("com.apple.SpeechRecognitionCore.speechrecognitiond"))
        #expect(CallClassifier.shouldIgnore("com.apple.siri.embeddedspeech"))
        #expect(!CallClassifier.shouldIgnore("com.apple.FaceTime"))
        #expect(!CallClassifier.shouldIgnore(nil))
    }

    @Test func helperBundles() {
        #expect(CallClassifier.appBundleIdentifier(forHelper: "com.google.Chrome.helper") == "com.google.Chrome")
        #expect(CallClassifier.appBundleIdentifier(forHelper: "com.google.Chrome.helper.Renderer") == "com.google.Chrome")
        #expect(CallClassifier.appBundleIdentifier(forHelper: "us.zoom.xos") == "us.zoom.xos")
    }

    @Test func headphoneSymbols() {
        #expect(HeadphoneSymbol.symbol(forDeviceName: "Sam’s AirPods Pro") == "airpodspro")
        #expect(HeadphoneSymbol.symbol(forDeviceName: "AirPods Max") == "airpodsmax")
        #expect(HeadphoneSymbol.symbol(forDeviceName: "AirPods") == "airpods")
        #expect(HeadphoneSymbol.symbol(forDeviceName: "Beats Studio Pro") == "beats.headphones")
        #expect(HeadphoneSymbol.symbol(forDeviceName: "WH-1000XM5") == "headphones")
    }

    @Test func gooFadesOutWithoutAJump() {
        #expect(GooMath.blurRadius(strength: 0) == 0)
        #expect(GooMath.blurRadius(strength: 2) == GooMath.maximumBlur)
        #expect(GooMath.alphaSlope(blurRadius: 0, displayScale: 2) == 1, "identity at rest")
        let slope = GooMath.alphaSlope(blurRadius: 7, displayScale: 2)
        #expect(slope > 10)
        #expect(abs(slope * 0.5 + GooMath.alphaBias(slope: slope) - 0.5) < 1e-9, "edge stays at half coverage")
    }

    @Test func accentFromArtwork() {
        let red: [UInt8] = (0..<64).map { $0 % 4 == 0 || $0 % 4 == 3 ? 255 : 0 }
        let accent = ColorMath.accent(fromRGBA: red)
        #expect(accent.red > 0.9 && accent.green < 0.6 && accent.blue < 0.6)
        let grey: [UInt8] = (0..<64).map { $0 % 4 == 3 ? 255 : 128 }
        #expect(ColorMath.accent(fromRGBA: grey) == .white)
        #expect(ColorMath.accent(fromRGBA: []) == .white)
        #expect(ColorMath.accent(fromRGBA: [UInt8](repeating: 0, count: 64)) == .white, "fully transparent")
    }

    @Test func hsbRoundTrip() {
        let colour = ColorMath.RGB(red: 0.2, green: 0.6, blue: 0.9)
        let (h, s, b) = ColorMath.hsb(colour)
        let back = ColorMath.rgb(hue: h, saturation: s, brightness: b)
        #expect(abs(back.red - colour.red) < 1e-9 && abs(back.green - colour.green) < 1e-9 && abs(back.blue - colour.blue) < 1e-9)
    }

    @Test func appearanceClamping() {
        let wild = NotchAppearance(style: .island, width: 9_999, height: -3, verticalOffset: .nan, horizontalOffset: -1e6, pitchBlack: false)
        let clamped = wild.clamped()
        #expect(clamped.width == NotchAppearance.widthRange.upperBound)
        #expect(clamped.height == NotchAppearance.heightRange.lowerBound)
        #expect(clamped.verticalOffset == NotchAppearance.standard.verticalOffset)
        #expect(clamped.horizontalOffset == NotchAppearance.horizontalOffsetRange.lowerBound)
        #expect(clamped.style == .island)
        #expect(!clamped.pitchBlack)
    }
}
