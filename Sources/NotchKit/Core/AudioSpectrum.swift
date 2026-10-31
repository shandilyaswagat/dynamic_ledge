import Accelerate
import Foundation
import Observation

public struct SpectrumBand: Equatable, Sendable {
    public let index: Int
    public let frequencyRange: ClosedRange<Double>
    public var magnitude: Double

    public init(index: Int, frequencyRange: ClosedRange<Double>, magnitude: Double = 0) {
        self.index = index
        self.frequencyRange = frequencyRange
        self.magnitude = magnitude
    }
}

public enum FFTProcessor {
    /// 5 standard visualization bands: Sub-bass (20-100Hz), Bass (100-300Hz),
    /// Midrange (300-1500Hz), Upper-mids (1500-5000Hz), Treble (5000-20000Hz)
    public static let standardBands: [ClosedRange<Double>] = [
        20...120,
        120...350,
        350...1500,
        1500...5000,
        5000...20000
    ]

    /// Calculates normalized 0...1 frequency band magnitudes from floating-point PCM audio samples.
    public static func computeBands(
        samples: [Float],
        sampleRate: Double = 44100,
        bandRanges: [ClosedRange<Double>] = standardBands
    ) -> [Double] {
        let count = samples.count
        guard count >= 16 else { return Array(repeating: 0.0, count: bandRanges.count) }

        // Apply Hann window
        var window = [Float](repeating: 0, count: count)
        vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
        var windowed = [Float](repeating: 0, count: count)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(count))

        // Power-of-2 length for DFT / FFT
        let log2n = vDSP_Length(floor(log2(Double(count))))
        let n = 1 << log2n
        let halfN = n / 2

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            return Array(repeating: 0.0, count: bandRanges.count)
        }
        defer { vDSP_destroy_fftsetup(setup) }

        var real = [Float](repeating: 0, count: halfN)
        var imag = [Float](repeating: 0, count: halfN)

        let bandOutputs = real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr -> [Double] in
                var splitComplex = DSPSplitComplex(
                    realp: realPtr.baseAddress!,
                    imagp: imagPtr.baseAddress!
                )

                windowed.withUnsafeBytes { rawPtr in
                    let complexPtr = rawPtr.bindMemory(to: DSPComplex.self)
                    vDSP_ctoz(complexPtr.baseAddress!, 2, &splitComplex, 1, vDSP_Length(halfN))
                }

                vDSP_fft_zrip(setup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                var magnitudes = [Float](repeating: 0, count: halfN)
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))

                let binWidth = sampleRate / Double(n)
                return bandRanges.map { range in
                    var sum: Double = 0
                    var binCount = 0
                    for (binIdx, power) in magnitudes.enumerated() {
                        let freq = Double(binIdx) * binWidth
                        if range.contains(freq) {
                            sum += Double(power)
                            binCount += 1
                        }
                    }
                    if binCount == 0 { return 0.0 }
                    let avg = sqrt(sum / Double(binCount))
                    // Normalize with logarithmic scaling
                    let db = 20 * log10(max(avg, 1e-5))
                    let normalized = (db + 60) / 60.0
                    return max(0.0, min(1.0, normalized))
                }
            }
        }

        return bandOutputs
    }
}

@MainActor
@Observable
public final class AudioSpectrumAnalyzer {
    public private(set) var bands: [Double] = [0.0, 0.0, 0.0, 0.0, 0.0]
    public private(set) var isCapturing = false

    public init() {}

    public func update(samples: [Float], sampleRate: Double = 44100) {
        let computed = FFTProcessor.computeBands(samples: samples, sampleRate: sampleRate)
        // Smooth transitions
        var smoothed = bands
        for i in 0..<min(bands.count, computed.count) {
            smoothed[i] = smoothed[i] * 0.4 + computed[i] * 0.6
        }
        bands = smoothed
    }

    public func reset() {
        bands = [0.0, 0.0, 0.0, 0.0, 0.0]
        isCapturing = false
    }
}
