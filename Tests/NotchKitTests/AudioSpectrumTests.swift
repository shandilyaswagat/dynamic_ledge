import Foundation
import Testing
@testable import NotchKit

@MainActor
@Suite("Audio spectrum and FFT analysis")
struct AudioSpectrumTests {
    @Test func computeBandsReturnsEmptyWhenBufferTooSmall() {
        let small = [Float](repeating: 0.1, count: 8)
        let bands = FFTProcessor.computeBands(samples: small)
        #expect(bands.count == FFTProcessor.standardBands.count)
        #expect(bands.allSatisfy { $0 == 0.0 })
    }

    @Test func computeBandsDetectsLowFrequencyEnergy() {
        let sampleRate = 44100.0
        let count = 512
        // Generate a 60 Hz sine wave (belongs in Sub-bass 20-120Hz band)
        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            samples[i] = Float(sin(2.0 * .pi * 60.0 * t))
        }

        let bands = FFTProcessor.computeBands(samples: samples, sampleRate: sampleRate)
        #expect(bands.count == 5)
        // Band 0 (Sub-bass) should have highest magnitude
        let subBass = bands[0]
        let treble = bands[4]
        #expect(subBass > treble)
        #expect(subBass > 0.3)
    }

    @Test func spectrumAnalyzerSmoothsUpdates() {
        let analyzer = AudioSpectrumAnalyzer()
        #expect(analyzer.bands == [0.0, 0.0, 0.0, 0.0, 0.0])

        var samples = [Float](repeating: 0, count: 256)
        for i in 0..<256 { samples[i] = Float(sin(Double(i) * 0.1)) }

        analyzer.update(samples: samples)
        #expect(analyzer.bands.count == 5)

        analyzer.reset()
        #expect(analyzer.bands.allSatisfy { $0 == 0.0 })
    }
}
