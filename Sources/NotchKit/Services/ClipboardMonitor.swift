import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers

/// Watches the pasteboard for copied text. macOS has no change notification, so it checks the
/// change count a little more than once a second, which costs next to nothing. Copies marked
/// private (passwords) are skipped. Only clips the user pins are saved, so they're still there
/// after a restart; the rest stays in memory. With `readsTextInImages`, a copied image's text is
/// read on this Mac and kept as a clip; the image itself isn't.
@MainActor
@Observable
public final class ClipboardMonitor {
    public private(set) var history: ClipboardHistory {
        didSet {
            if history.pinned != oldValue.pinned { savePinned() }
        }
    }
    /// The entry that was just copied back, for a moment of feedback on its card.
    public private(set) var justCopied: UUID?

    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private let defaults: UserDefaults
    private static let pinnedKey = "clipboard.pinned"
    @ObservationIgnored private var lastChangeCount: Int
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var feedbackTask: Task<Void, Never>?
    /// Text from images (Settings › Home & Widgets). Off by default.
    @ObservationIgnored public var readsTextInImages = false
    @ObservationIgnored var excludedApps = ""
    var keepsImages = false {
        didSet {
            if !keepsImages {
                imageCapture?.cancel()
                images.removeAll()
            }
        }
    }
    private(set) var images: [CopiedImage] = []
    @ObservationIgnored private(set) var imageCapture: Task<Void, Never>?
    private nonisolated static let imageBudget = 32 * 1024 * 1024
    private static let imageCapacity = 6

    struct CopiedImage: Identifiable, Sendable {
        let id = UUID()
        let png: Data
        let thumbnail: CGImage
        let appName: String?

        nonisolated static func make(from data: Data, appName: String?) -> Self? {
            let limits = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, limits),
                  let original = downsample(source, to: 2560),
                  let thumbnail = downsample(source, to: 300) else { return nil }
            let png = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(destination, original, nil)
            guard CGImageDestinationFinalize(destination), png.length <= ClipboardMonitor.imageBudget else { return nil }
            return Self(png: png as Data, thumbnail: thumbnail, appName: appName)
        }

        private nonisolated static func downsample(_ source: CGImageSource, to size: Int) -> CGImage? {
            CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
            ] as CFDictionary)
        }
    }
    /// Reading the last copied image, if it's still going.
    @ObservationIgnored private(set) var recognition: Task<Void, Never>?

    public init(pasteboard: NSPasteboard = .general, defaults: UserDefaults = .standard) {
        self.pasteboard = pasteboard
        self.defaults = defaults
        let pinned = defaults.data(forKey: Self.pinnedKey)
            .flatMap { try? JSONDecoder().decode([ClipboardHistory.Entry].self, from: $0) } ?? []
        history = ClipboardHistory(pinned: pinned)
        lastChangeCount = pasteboard.changeCount
    }

    public var isRunning: Bool { timer != nil }

    public func start() {
        guard timer == nil else { return }
        // Whatever was on the pasteboard before watching started isn't a new copy.
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops watching and forgets the history, apart from pinned clips.
    public func stop() {
        timer?.invalidate()
        timer = nil
        removeAll()
    }

    public func check() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard ClipboardRules.shouldRecord(types: types) else { return }
        let app = NSWorkspace.shared.frontmostApplication
        let appName = app?.localizedName
        guard !ClipboardRules.excludesApp(name: appName, bundleID: app?.bundleIdentifier, exclusions: excludedApps) else { return }
        if let text = pasteboard.string(forType: .string) {
            history.add(text, appName: appName)
            return
        }
        guard readsTextInImages || keepsImages, ClipboardRules.isImage(types: types),
              let image = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else { return }
        if keepsImages, image.count <= 64 * 1024 * 1024 { captureImage(image, appName: appName) }
        guard readsTextInImages else { return }
        recognition?.cancel()
        recognition = Task { [weak self] in
            let text = await TextRecognizer.text(in: image)
            guard !Task.isCancelled, let self, self.isRunning, let text else { return }
            self.history.add(text, appName: appName)
        }
    }

    private func captureImage(_ data: Data, appName: String?) {
        imageCapture?.cancel()
        imageCapture = Task { [weak self] in
            let worker = Task.detached(priority: .utility) { CopiedImage.make(from: data, appName: appName) }
            let clip = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled, let self, self.keepsImages, let clip else { return }
            storeImage(clip)
        }
    }

    private func storeImage(_ clip: CopiedImage) {
        images.removeAll { $0.png == clip.png }
        images.insert(clip, at: 0)
        var bytesLeft = Self.imageBudget
        images = Array(images.prefix(Self.imageCapacity).prefix { image in
            bytesLeft -= image.png.count
            return bytesLeft >= 0
        })
    }

    func copyImage(_ clip: CopiedImage) {
        pasteboard.clearContents()
        pasteboard.setData(clip.png, forType: .png)
        lastChangeCount = pasteboard.changeCount
        storeImage(clip)
        showCopied(clip.id)
    }

    /// Puts an entry back on the pasteboard so it can be pasted, and moves it to the front
    /// (pinned clips stay where they are).
    public func copy(_ entry: ClipboardHistory.Entry) {
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        // Our own copy is not a new entry; just move this one to the front.
        lastChangeCount = pasteboard.changeCount
        history.add(entry.text, appName: entry.appName)
        // A pinned clip keeps its place; anything else is now first among the unpinned.
        showCopied(history.entries.first { $0.text == entry.text }?.id)
    }

    private func showCopied(_ id: UUID?) {
        justCopied = id
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.justCopied = nil
        }
    }

    public func remove(_ id: UUID) {
        history.remove(id)
        images.removeAll { $0.id == id }
    }

    /// Clears the history; pinned clips stay.
    public func removeAll() {
        recognition?.cancel()
        recognition = nil
        imageCapture?.cancel()
        imageCapture = nil
        images.removeAll()
        history.removeAll()
    }

    /// Returns false when every pin is taken.
    @discardableResult
    public func togglePin(_ id: UUID) -> Bool {
        history.togglePin(id)
    }

    private func savePinned() {
        let pinned = history.pinned
        if pinned.isEmpty {
            defaults.removeObject(forKey: Self.pinnedKey)
        } else if let data = try? JSONEncoder().encode(pinned) {
            defaults.set(data, forKey: Self.pinnedKey)
        }
    }
}
