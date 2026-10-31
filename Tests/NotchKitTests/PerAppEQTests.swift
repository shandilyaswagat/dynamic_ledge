import Foundation
import Testing
@testable import NotchKit

@MainActor
@Suite("Per-app EQ and DSP engine")
struct PerAppEQTests {
    @Test func peakingFilterBypassOnZeroGain() {
        let coeffs = AudioDSP.peakingFilter(frequency: 1000, gainDB: 0)
        #expect(coeffs.b0 == 1)
        #expect(coeffs.b1 == 0)
        #expect(coeffs.b2 == 0)
        #expect(coeffs.a1 == 0)
        #expect(coeffs.a2 == 0)

        let input = [1.0, 2.0, 3.0]
        let output = AudioDSP.process(samples: input, coefficients: coeffs)
        #expect(output == input)
    }

    @Test func peakingFilterBoostsSignal() {
        let coeffs = AudioDSP.peakingFilter(frequency: 1000, gainDB: 6.0, q: 1.0, sampleRate: 44100)
        #expect(coeffs.b0 > 0)
        // Processing a 1kHz resonant input should yield higher amplitude than zero gain
        var samples = [Double](repeating: 0, count: 128)
        for i in 0..<128 {
            samples[i] = sin(2.0 * .pi * 1000.0 * Double(i) / 44100.0)
        }
        let output = AudioDSP.process(samples: samples, coefficients: coeffs)
        #expect(output.count == 128)
        let maxInput = samples.map(abs).max() ?? 0
        let maxOutput = output.dropFirst(20).map(abs).max() ?? 0
        #expect(maxOutput > maxInput)
    }

    @Test func perAppProfilesAndRecovery() {
        let engine = PerAppEQEngine()
        let musicProfile = EQProfile(bundleIdentifier: "com.apple.Music", gains: EQPreset.bassBoost.bandGains)
        engine.setProfile(musicProfile)

        engine.activateApp(bundleIdentifier: "com.apple.Music")
        #expect(engine.activeProfile()?.bundleIdentifier == "com.apple.Music")
        #expect(engine.activeProfile()?.gains == EQPreset.bassBoost.bandGains)

        engine.activateApp(bundleIdentifier: "com.apple.Safari")
        #expect(engine.activeProfile() == nil)

        engine.activateApp(bundleIdentifier: "com.apple.Music")
        engine.globalBypass = true
        #expect(engine.activeProfile() == nil)

        engine.resetAndRecover()
        #expect(!engine.globalBypass)
        #expect(engine.activeAppBundleID == nil)
    }
}
