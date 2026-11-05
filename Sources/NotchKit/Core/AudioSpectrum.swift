import Accelerate
import Foundation
import Observation

/// Turns a short run of audio into how loud each frequency band is, for the music bars.
public enum FFTProcessor {
    /// One range per music bar: bass, low mids, high mids, treble.
    public static let barBands: [ClosedRange<Double>] = [
        40...250,
        250...1000,
        1000...4000,
        4000...12000,
    ]

    /// Music has much less energy in the highs, so higher bands are lifted to move as much.
    public static let barTilt: [Double] = [0, 3, 8, 14]

    /// Quieter than this shows as an empty bar.
    static let floorDecibels = -70.0
    /// Loudness from the floor to full scale, in decibels.
    static let rangeDecibels = 60.0

    /// Each band's level from 0 (silent) to 1 (very loud), on a decibel scale. Uses the largest
    /// power of two of `samples` that fits.
    public static func computeBands(
        samples: [Float],
        sampleRate: Double = 48000,
        bandRanges: [ClosedRange<Double>] = barBands,
        tilt: [Double] = barTilt
    ) -> [Double] {
        guard samples.count >= 16, sampleRate > 0, let meter = SpectrumMeter(size: samples.count) else {
            return Array(repeating: 0, count: bandRanges.count)
        }
        return meter.bands(samples, sampleRate: sampleRate, bandRanges: bandRanges, tilt: tilt)
    }
}

/// The FFT set-up, window and buffers for one window size, made once and reused, so measuring 30
/// times a second allocates nothing. Use it from one thread at a time.
final class SpectrumMeter {
    let size: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var window: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var magnitudes: [Float]

    /// The largest power of two up to `size`; nil below 16 samples.
    init?(size: Int) {
        guard size >= 16 else { return nil }
        log2n = vDSP_Length(log2(Double(size)).rounded(.down))
        self.size = 1 << log2n
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        self.setup = setup
        window = [Float](repeating: 0, count: self.size)
        vDSP_hann_window(&window, vDSP_Length(self.size), Int32(vDSP_HANN_NORM))
        windowed = [Float](repeating: 0, count: self.size)
        real = [Float](repeating: 0, count: self.size / 2)
        imag = [Float](repeating: 0, count: self.size / 2)
        magnitudes = [Float](repeating: 0, count: self.size / 2)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Measures the last `size` samples.
    func bands(
        _ samples: [Float],
        sampleRate: Double,
        bandRanges: [ClosedRange<Double>] = FFTProcessor.barBands,
        tilt: [Double] = FFTProcessor.barTilt
    ) -> [Double] {
        guard samples.count >= size, sampleRate > 0 else { return Array(repeating: 0, count: bandRanges.count) }
        let n = size
        let halfN = n / 2
        samples.withUnsafeBufferPointer { buffer in
            vDSP_vmul(buffer.baseAddress! + (samples.count - n), 1, window, 1, &windowed, 1, vDSP_Length(n))
        }
        real.withUnsafeMutableBufferPointer { realPointer in
            imag.withUnsafeMutableBufferPointer { imagPointer in
                var split = DSPSplitComplex(realp: realPointer.baseAddress!, imagp: imagPointer.baseAddress!)
                windowed.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(halfN))
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        // The real FFT comes back doubled and summed over n samples: this makes a full-scale
        // sine about 0 dB.
        let scale = 1 / Double(n)
        let binWidth = sampleRate / Double(n)
        return bandRanges.enumerated().map { index, range in
            let first = max(1, Int((range.lowerBound / binWidth).rounded(.up)))
            let last = min(halfN - 1, Int((range.upperBound / binWidth).rounded(.down)))
            guard first <= last else { return 0 }
            // The loudest bin, so a band of many bins isn't drowned by its quiet ones.
            let peak = magnitudes[first...last].max() ?? 0
            let amplitude = Double(peak).squareRoot() * scale
            let decibels = 20 * log10(max(amplitude, 1e-9)) + (tilt.indices.contains(index) ? tilt[index] : 0)
            return min(max((decibels - FFTProcessor.floorDecibels) / FFTProcessor.rangeDecibels, 0), 1)
        }
    }
}

/// The music bars' levels, smoothed so they rise quickly and fall gently, like a real meter.
@MainActor
@Observable
public final class AudioSpectrumAnalyzer {
    public private(set) var bands: [Double]
    /// True while real levels are coming in. A tap that only hears silence (macOS access was
    /// refused, or a quiet passage) turns it off after a moment, so the bars go back to their
    /// own motion instead of lying flat.
    public private(set) var isCapturing = false
    @ObservationIgnored private var silentSince: Date?

    /// How long silence lasts before the bars stop following the sound.
    static let silenceTimeout: TimeInterval = 2

    public init(barCount: Int = FFTProcessor.barBands.count) {
        bands = Array(repeating: 0, count: barCount)
    }

    public func update(samples: [Float], sampleRate: Double = 48000) {
        update(levels: FFTProcessor.computeBands(samples: samples, sampleRate: sampleRate))
    }

    public func update(levels: [Double], now: Date = Date()) {
        if levels.allSatisfy({ $0 < 0.02 }) {
            let since = silentSince ?? now
            silentSince = since
            if now.timeIntervalSince(since) >= Self.silenceTimeout {
                if isCapturing { reset() }
                return
            }
        } else {
            silentSince = nil
            isCapturing = true
        }
        var smoothed = bands
        for index in 0..<min(smoothed.count, levels.count) {
            let rising = levels[index] > smoothed[index]
            let weight = rising ? 0.7 : 0.35
            smoothed[index] += (levels[index] - smoothed[index]) * weight
        }
        bands = smoothed
    }

    public func reset() {
        bands = Array(repeating: 0, count: bands.count)
        isCapturing = false
        silentSince = nil
    }
}
