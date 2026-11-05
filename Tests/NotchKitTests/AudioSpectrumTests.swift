import Foundation
import Testing
@testable import NotchKit

@MainActor
@Suite("Audio spectrum and FFT analysis")
struct AudioSpectrumTests {
    private func sine(_ frequency: Double, amplitude: Float = 0.5, count: Int = 1024, sampleRate: Double = 48000) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    @Test func computeBandsReturnsSilenceWhenBufferTooSmall() {
        let bands = FFTProcessor.computeBands(samples: [Float](repeating: 0.1, count: 8))
        #expect(bands.count == FFTProcessor.barBands.count)
        #expect(bands.allSatisfy { $0 == 0 })
    }

    @Test func eachToneLightsItsOwnBar() {
        for (index, frequency) in [100.0, 500, 2000, 8000].enumerated() {
            let bands = FFTProcessor.computeBands(samples: sine(frequency))
            #expect(bands.indices.max { bands[$0] < bands[$1] } == index, "\(frequency) Hz")
            #expect(bands[index] > 0.5)
        }
    }

    @Test func silenceIsAnEmptyBarAndLoudIsFull() {
        #expect(FFTProcessor.computeBands(samples: [Float](repeating: 0, count: 1024)).allSatisfy { $0 == 0 })
        #expect(FFTProcessor.computeBands(samples: sine(100, amplitude: 1))[0] > 0.9)
        #expect(FFTProcessor.computeBands(samples: sine(100, amplitude: 0.01))[0] < FFTProcessor.computeBands(samples: sine(100))[0])
    }

    @Test func barsRiseFastAndFallGently() {
        let analyzer = AudioSpectrumAnalyzer()
        analyzer.update(levels: [1, 1, 1, 1])
        #expect(analyzer.isCapturing)
        let risen = analyzer.bands[0]
        #expect(risen > 0.6)
        analyzer.update(levels: [0.1, 0.1, 0.1, 0.1])
        #expect(analyzer.bands[0] < risen)
        #expect(analyzer.bands[0] > 0.3, "falls in steps, not at once")
        analyzer.reset()
        #expect(analyzer.bands.allSatisfy { $0 == 0 })
        #expect(!analyzer.isCapturing)
    }

    @Test func lastingSilenceHandsTheBarsBack() {
        // A refused macOS prompt means the tap hears only silence.
        let analyzer = AudioSpectrumAnalyzer()
        let start = Date()
        analyzer.update(levels: [0.5, 0.5, 0.5, 0.5], now: start)
        analyzer.update(levels: [0, 0, 0, 0], now: start.addingTimeInterval(0.5))
        #expect(analyzer.isCapturing, "a short pause in the music")
        analyzer.update(levels: [0, 0, 0, 0], now: start.addingTimeInterval(3))
        #expect(!analyzer.isCapturing)
        analyzer.update(levels: [0.5, 0.5, 0.5, 0.5], now: start.addingTimeInterval(4))
        #expect(analyzer.isCapturing)
    }
}
