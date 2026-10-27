import Foundation
import ImageIO
import os

/// Runs the media helper inside /usr/bin/perl and talks to it over pipes.
@MainActor
final class MediaBridgeClient {
    enum State: Equatable {
        case stopped
        case running
        /// The helper library is missing or keeps crashing. Now Playing is off until relaunch.
        case unavailable
    }

    var onMessage: ((ParsedBridgeMessage) -> Void)?
    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .stopped {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    private var process: Process?
    private var input: FileHandle?
    private var reader = BridgeLineReader()
    private var recentLaunches: [Date] = []
    private var isStopping = false
    private let log = Logger(subsystem: Log.subsystem, category: "media-bridge")

    nonisolated static let libraryName = "libNotchMediaBridge.dylib"
    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    private static let script = """
    use strict; use warnings; use DynaLoader;
    my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die "load: " . DynaLoader::dl_error() . "\\n";
    my $sym = DynaLoader::dl_find_symbol($lib, "notch_media_stream") or die "missing symbol\\n";
    DynaLoader::dl_install_xsub("main::notch_media_stream", $sym)->();
    """

    func start() {
        isStopping = false
        launch()
    }

    func stop() {
        isStopping = true
        try? input?.close()
        input = nil
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        reader = BridgeLineReader()
        state = .stopped
    }

    func send(_ command: String) {
        guard let input else { return }
        // SIGPIPE is ignored app-wide, so a dead helper surfaces as a thrown error here.
        do {
            try input.write(contentsOf: Data((command + "\n").utf8))
        } catch {
            log.error("Failed to send command: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func locateLibrary(bundle: Bundle = .main) -> URL? {
        let candidates = [
            bundle.privateFrameworksURL?.appendingPathComponent(libraryName),
            bundle.resourceURL?.appendingPathComponent(libraryName),
            bundle.executableURL?.deletingLastPathComponent().appendingPathComponent(libraryName),
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// A downloaded app carries the quarantine flag on every file inside it. Once the user has
    /// opened the app that's fine for the app itself, but Perl loading the helper library would
    /// trigger a separate "not opened" warning and fail. A copy written by the app has no
    /// quarantine flag and keeps the library's own signature.
    nonisolated static func unquarantinedCopy(of library: URL, in folder: URL? = nil, fileManager: FileManager = .default) -> URL? {
        guard
            let folder = folder ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Dynamic Ledge", isDirectory: true),
            let bytes = try? Data(contentsOf: library)
        else { return nil }
        let copy = folder.appendingPathComponent(libraryName)
        do {
            if (try? Data(contentsOf: copy)) != bytes {
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                try bytes.write(to: copy, options: .atomic)
            }
            removexattr(copy.path, "com.apple.quarantine", 0)
            return copy
        } catch {
            return nil
        }
    }

    private func launch() {
        guard FileManager.default.isExecutableFile(atPath: Self.perl.path) else {
            log.error("/usr/bin/perl is missing; Now Playing is unavailable")
            state = .unavailable
            return
        }
        guard let bundled = Self.locateLibrary() else {
            log.error("\(Self.libraryName, privacy: .public) not found; Now Playing is unavailable")
            state = .unavailable
            return
        }
        let library = Self.unquarantinedCopy(of: bundled) ?? bundled

        let now = Date()
        recentLaunches = recentLaunches.filter { now.timeIntervalSince($0) < 300 } + [now]
        guard recentLaunches.count <= 5 else {
            log.error("Media helper crashed repeatedly; giving up until next launch")
            state = .unavailable
            return
        }

        let process = Process()
        process.executableURL = Self.perl
        process.arguments = ["-e", Self.script, library.path]
        let output = Pipe()
        let input = Pipe()
        process.standardOutput = output
        process.standardInput = input
        process.standardError = FileHandle.nullDevice

        // Parsing (JSON, base64 artwork, tint) happens on the reader's queue; only finished
        // messages reach the main thread, in order.
        let reader = BridgeLineReader()
        self.reader = reader
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            reader.append(data) { messages in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.deliver(messages, from: reader) }
                }
            }
        }
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.handleTermination(of: finished, status: status) }
            }
        }

        do {
            try process.run()
            self.process = process
            self.input = input.fileHandleForWriting
            state = .running
        } catch {
            log.error("Failed to start media helper: \(error.localizedDescription, privacy: .public)")
            state = .unavailable
        }
    }

    private func deliver(_ messages: [ParsedBridgeMessage], from source: BridgeLineReader) {
        // Lines from a helper that has since been replaced are stale.
        guard source === reader else { return }
        for parsed in messages {
            if case .error(let reason) = parsed.message {
                log.error("Media helper error: \(reason, privacy: .public)")
            }
            onMessage?(parsed)
        }
    }

    private func handleTermination(of finished: Process, status: Int32) {
        guard finished === process else { return }
        process = nil
        input = nil
        guard !isStopping else { return }
        log.notice("Media helper exited with status \(status); restarting")
        state = .stopped
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isStopping, self.process == nil, self.state != .unavailable else { return }
                self.launch()
            }
        }
    }
}

/// A helper message plus the tint of any artwork it carried, worked out off the main thread.
struct ParsedBridgeMessage: Sendable {
    let message: BridgeMessage
    let artworkAccent: ColorMath.RGB?
}

/// Splits helper output into lines and parses them on a private serial queue.
final class BridgeLineReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "notch.media.reader", qos: .utility)
    /// Only touched on `queue`.
    private var buffer = Data()
    /// A runaway helper must not grow memory without bound.
    static let maximumBuffer = 8 * 1024 * 1024

    func append(_ data: Data, deliver: @escaping @Sendable ([ParsedBridgeMessage]) -> Void) {
        queue.async {
            let messages = self.consume(data)
            if !messages.isEmpty {
                deliver(messages)
            }
        }
    }

    /// Synchronous core, also used by tests.
    func consume(_ data: Data) -> [ParsedBridgeMessage] {
        buffer.append(data)
        var messages: [ParsedBridgeMessage] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.isEmpty, let message = BridgeMessage.parse(line) else { continue }
            var accent: ColorMath.RGB?
            if case .nowPlaying(_, let artwork?) = message {
                accent = ArtworkTint.accent(of: artwork)
            }
            messages.append(ParsedBridgeMessage(message: message, artworkAccent: accent))
        }
        if buffer.count > Self.maximumBuffer {
            buffer.removeAll()
        }
        return messages
    }
}

enum ArtworkTint {
    /// Decodes a small thumbnail of the artwork and picks its accent colour. Safe off the main thread.
    static func accent(of data: Data) -> ColorMath.RGB {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 32,
            ] as CFDictionary)
        else { return .white }
        let side = 12
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(thumbnail, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? ColorMath.accent(fromRGBA: pixels) : .white
    }
}
