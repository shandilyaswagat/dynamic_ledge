import AppKit
import Observation
import QuickLookThumbnailing

/// A bounded, session-only shelf of references. Originals are never copied or deleted.
@MainActor
@Observable
public final class TrayStore {
    public struct Item: Identifiable, Equatable, Sendable, Codable {
        public let id: UUID
        public let url: URL
        public let addedAt: Date
        public var sourceURL: URL? = nil

        public var name: String {
            if let sourceURL, !sourceURL.isFileURL { return (sourceURL.host ?? "Web Link") + sourceURL.path }
            if url.pathExtension == "app" || url.pathExtension == "webloc" {
                return url.deletingPathExtension().lastPathComponent
            }
            return url.lastPathComponent
        }
    }

    public private(set) var items: [Item] = []
    /// Quick Look thumbnails, filled in lazily.
    public private(set) var thumbnails: [UUID: NSImage] = [:]
    public private(set) var statusMessage: String?

    public static let capacity = 30

    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let sessionFolder: URL

    /// `folder` injects a base directory for tests. Generated shortcuts belong to this instance.
    public init(folder: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        sessionFolder = (folder ?? fileManager.temporaryDirectory)
            .appendingPathComponent("DynamicNotch-Tray-" + UUID().uuidString, isDirectory: true)
    }

    deinit { try? FileManager.default.removeItem(at: sessionFolder) }

    private func makeWebloc(for url: URL) throws -> URL {
        try fileManager.createDirectory(at: sessionFolder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let file = sessionFolder.appendingPathComponent(UUID().uuidString + ".webloc")
        let data = try PropertyListSerialization.data(fromPropertyList: ["URL": url.absoluteString], format: .xml, options: 0)
        try data.write(to: file, options: .atomic)
        return file
    }

    public func reportFailure(_ message: String) { statusMessage = message }

    // MARK: Changes

    /// Adds files, skipping ones already in the tray and anything that isn't a file on disk.
    /// Web URLs (http/https) are saved as standard macOS .webloc internet shortcuts.
    /// Returns how many were added.
    @discardableResult
    public func add(_ urls: [URL], now: Date = Date()) -> Int {
        pruneMissing()
        var existing = Set(items.map { ($0.sourceURL ?? $0.url).absoluteString })
        var added: [Item] = []
        var overflow = false
        var writeFailure = false
        for input in urls where DropPolicy.isSupported(input) {
            let source = input.isFileURL ? input.standardizedFileURL : input
            guard !existing.contains(source.absoluteString) else { continue }
            guard items.count + added.count < Self.capacity else { overflow = true; continue }
            do {
                let local: URL
                if source.isFileURL {
                    guard fileManager.fileExists(atPath: source.path) else { continue }
                    local = source
                } else {
                    local = try makeWebloc(for: source)
                }
                existing.insert(source.absoluteString)
                added.append(Item(id: UUID(), url: local, addedAt: now, sourceURL: source))
            } catch { writeFailure = true }
        }
        statusMessage = overflow ? "Tray full — remove an item to add another." :
            (added.isEmpty ? "No new files added. The file may already be here or unavailable." : nil)
        if writeFailure { statusMessage = "Could not create a web shortcut. Check available disk space and permissions." }
        guard !added.isEmpty else { return 0 }
        items = added.reversed() + items
        added.forEach(loadThumbnail)
        return added.count
    }

    public func remove(_ id: UUID) {
        if let item = items.first(where: { $0.id == id }), item.url.deletingLastPathComponent() == sessionFolder {
            try? fileManager.removeItem(at: item.url)
        }
        items.removeAll { $0.id == id }
        thumbnails[id] = nil
        statusMessage = nil
    }

    public func removeAll() {
        try? fileManager.removeItem(at: sessionFolder)
        items.removeAll()
        thumbnails.removeAll()
        statusMessage = nil
    }

    /// Drops items whose files were moved or deleted since they were added.
    public func pruneMissing() {
        let kept = items.filter { fileManager.fileExists(atPath: $0.url.path) }
        guard kept.count != items.count else { return }
        let keptIDs = Set(kept.map(\.id))
        thumbnails = thumbnails.filter { keptIDs.contains($0.key) }
        items = kept
    }

    // MARK: Actions

    public func open(_ item: Item) {
        NSWorkspace.shared.open(item.url)
    }

    public func revealInFinder(_ item: Item) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    public func icon(for item: Item) -> NSImage {
        thumbnails[item.id] ?? NSWorkspace.shared.icon(forFile: item.url.path)
    }

    private func loadThumbnail(_ item: Item) {
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: 64, height: 64),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        let id = item.id
        // Quick Look answers on its own queue, so this closure isn't tied to the main actor
        // (Swift would stop the app); only the image hops back.
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { @Sendable [weak self] representation, _ in
            guard let cgImage = representation?.cgImage else { return }
            let size = NSSize(width: cgImage.width, height: cgImage.height)
            let image = cgImage
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.items.contains(where: { $0.id == id }) else { return }
                    self.thumbnails[id] = NSImage(cgImage: image, size: size)
                }
            }
        }
    }
}
