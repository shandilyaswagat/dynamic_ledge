import AudioToolbox
import CoreAudio
import Foundation
import os

/// Listens to what the Mac is playing through a Core Audio tap (macOS 14.2 and later) and turns
/// it into levels for the music bars, about 30 times a second. The sound is only measured, in
/// memory, a few milliseconds at a time: nothing is recorded, saved or sent. macOS asks once
/// before the first tap; if the user says no, the tap hears silence.
final class SystemAudioTap: @unchecked Sendable {
    /// Called on a background queue with a level from 0 to 1 per music bar.
    var onLevels: (@Sendable ([Double]) -> Void)?

    private let queue = DispatchQueue(label: "DynamicLedge.audio-tap", qos: .userInteractive)
    private let log = Logger(subsystem: Log.subsystem, category: "audio-tap")
    // Set up and torn down on the main actor; the IO block only touches the samples below.
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    /// The output the tap is clocked from; the tap is rebuilt when the Mac switches outputs.
    private(set) var outputDevice = AudioDeviceID(kAudioObjectUnknown)
    // Confined to `queue`.
    private var samples: [Float] = []
    private var sampleRate = 48000.0
    private var lastLevels: UInt64 = 0

    static let windowSize = 1024
    static let interval: UInt64 = 33_000_000

    static var isSupported: Bool {
        if #available(macOS 14.2, *) { true } else { false }
    }

    var isRunning: Bool { procID != nil }

    /// Starts listening, clocked from `output` (the Mac's current output), as Apple's sample does.
    @discardableResult
    func start(output: AudioDeviceID = AudioHW.defaultOutputDevice()) -> Bool {
        guard procID == nil else { return true }
        guard #available(macOS 14.2, *),
              let outputUID = AudioHW.string(output, AudioHW.address(kAudioDevicePropertyDeviceUID)) else { return false }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else {
            log.notice("Couldn't create the audio tap")
            return false
        }
        tapID = tap

        // Levels are read as 32-bit floats, which is what taps deliver.
        guard let format = Self.format(of: tap), format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
            log.notice("The audio tap's format isn't 32-bit float")
            stop()
            return false
        }
        let rate = format.mSampleRate > 0 ? format.mSampleRate : 48000
        queue.sync { sampleRate = rate; samples.removeAll(keepingCapacity: true) }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Dynamic Ledge music bars",
            kAudioAggregateDeviceUIDKey: "DynamicLedge.bars.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        var device = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device) == noErr else {
            log.notice("Couldn't create the tap's device")
            stop()
            return false
        }
        aggregateID = device

        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue) { [weak self] _, input, _, _, _ in
            self?.receive(input)
        }
        guard status == noErr, let proc else {
            stop()
            return false
        }
        procID = proc
        guard AudioDeviceStart(device, proc) == noErr else {
            stop()
            return false
        }
        outputDevice = output
        return true
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown, #available(macOS 14.2, *) {
            AudioHardwareDestroyProcessTap(tapID)
        }
        tapID = AudioObjectID(kAudioObjectUnknown)
        outputDevice = AudioDeviceID(kAudioObjectUnknown)
    }

    deinit { stop() }

    /// Mixes each buffer down to mono, keeps the latest window and measures it at most every
    /// `interval`.
    private func receive(_ input: UnsafePointer<AudioBufferList>) {
        // Interleaved (one buffer, both channels) or not (a buffer per channel).
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let channelCount = buffers.reduce(0) { $0 + max(Int($1.mNumberChannels), 1) }
        guard channelCount > 0, let first = buffers.first else { return }
        let frames = Int(first.mDataByteSize) / (MemoryLayout<Float>.size * max(Int(first.mNumberChannels), 1))
        let start = samples.count
        samples.append(contentsOf: repeatElement(0, count: frames))
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let channels = max(Int(buffer.mNumberChannels), 1)
            let floats = data.assumingMemoryBound(to: Float.self)
            let available = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels))
            for frame in 0..<available {
                for channel in 0..<channels { samples[start + frame] += floats[frame * channels + channel] }
            }
        }
        let scale = 1 / Float(channelCount)
        for index in start..<samples.count { samples[index] *= scale }
        if samples.count > Self.windowSize * 2 {
            samples.removeFirst(samples.count - Self.windowSize)
        }
        let now = DispatchTime.now().uptimeNanoseconds
        guard samples.count >= Self.windowSize, now - lastLevels >= Self.interval else { return }
        lastLevels = now
        let levels = FFTProcessor.computeBands(samples: Array(samples.suffix(Self.windowSize)), sampleRate: sampleRate)
        onLevels?(levels)
    }

    private static func format(of tap: AudioObjectID) -> AudioStreamBasicDescription? {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioHW.address(kAudioTapPropertyFormat)
        guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format) == noErr else { return nil }
        return format
    }
}
