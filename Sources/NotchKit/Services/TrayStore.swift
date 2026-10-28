import AppKit
import Observation
import QuickLookThumbnailing

/// A bounded shelf of references. Originals are never copied or deleted. Items clear when the app
/// quits, except pinned ones, which are remembered (by a Finder bookmark, so a renamed or moved
/// file is still found) and come back on the next launch.
@MainActor
@Observable
public final class TrayStore {
    public struct Item: Identifiable, Equatable, Sendable, Codable {
        public let id: UUID
        public let url: URL
        public let addedAt: Date
        public var sourceURL: URL? = nil
        public var isPinned = false

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

    /// Pinned first (newest pin first), then the rest, newest first.
    public var ordered: [Item] {
        items.filter(\.isPinned) + items.filter { !$0.isPinned }
    }

    public var pinnedCount: Int { items.lazy.filter(\.isPinned).count }

    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let sessionFolder: URL
    @ObservationIgnored private let defaults: UserDefaults?
    private static let pinnedKey = "tray.pinned"

    /// What's saved for a pinned item: a bookmark for a file, the address for a web link.
    private struct PinnedRecord: Codable {
        var id: UUID
        var addedAt: Date
        var bookmark: Data?
        var path: String?
        var webURL: URL?
    }

    /// `folder` injects a base directory for tests. Generated shortcuts belong to this instance.
    /// Pinned items are saved to `defaults`; pass nil to keep nothing.
    public init(folder: URL? = nil, fileManager: FileManager = .default, defaults: UserDefaults? = .standard) {
        self.fileManager = fileManager
        self.defaults = defaults
        sessionFolder = (folder ?? fileManager.temporaryDirectory)
            .appendingPathComponent("DynamicNotch-Tray-" + UUID().uuidString, isDirectory: true)
        restorePinned()
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
        let wasPinned = items.first { $0.id == id }?.isPinned == true
        if let item = items.first(where: { $0.id == id }) { deleteShortcut(item) }
        items.removeAll { $0.id == id }
        thumbnails[id] = nil
        statusMessage = nil
        if wasPinned { savePinned() }
    }

    /// Clears the tray. Pinned items stay.
    public func removeAll() {
        let cleared = items.filter { !$0.isPinned }
        cleared.forEach(deleteShortcut)
        let clearedIDs = Set(cleared.map(\.id))
        items.removeAll { clearedIDs.contains($0.id) }
        thumbnails = thumbnails.filter { !clearedIDs.contains($0.key) }
        statusMessage = nil
    }

    /// The app is quitting: the shortcuts it made go. Pinned items are already saved and are
    /// rebuilt on the next launch.
    public func endSession() {
        try? fileManager.removeItem(at: sessionFolder)
    }

    /// Pins or unpins an item. A pinned item goes to the front and is kept after quitting.
    public func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: index)
        item.isPinned.toggle()
        items.insert(item, at: 0)
        savePinned()
    }

    /// Drops items whose files were moved or deleted since they were added.
    public func pruneMissing() {
        let kept = items.filter { fileManager.fileExists(atPath: $0.url.path) }
        guard kept.count != items.count else { return }
        let keptIDs = Set(kept.map(\.id))
        let lostPin = items.contains { $0.isPinned && !keptIDs.contains($0.id) }
        thumbnails = thumbnails.filter { keptIDs.contains($0.key) }
        items = kept
        if lostPin { savePinned() }
    }

    private func deleteShortcut(_ item: Item) {
        if item.url.deletingLastPathComponent() == sessionFolder {
            try? fileManager.removeItem(at: item.url)
        }
    }

    // MARK: Pinned

    private func savePinned() {
        guard let defaults else { return }
        let records = items.filter(\.isPinned).map { item -> PinnedRecord in
            if let source = item.sourceURL, !source.isFileURL {
                return PinnedRecord(id: item.id, addedAt: item.addedAt, webURL: source)
            }
            return PinnedRecord(
                id: item.id,
                addedAt: item.addedAt,
                bookmark: try? item.url.bookmarkData(),
                path: item.url.path
            )
        }
        if records.isEmpty {
            defaults.removeObject(forKey: Self.pinnedKey)
        } else if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.pinnedKey)
        }
    }

    /// Brings back last session's pins. A file that's gone is dropped; one that was moved or
    /// renamed is followed through its bookmark.
    private func restorePinned() {
        guard let data = defaults?.data(forKey: Self.pinnedKey),
              let records = try? JSONDecoder().decode([PinnedRecord].self, from: data) else { return }
        var restored: [Item] = []
        for record in records.prefix(Self.capacity) {
            if let web = record.webURL {
                guard let local = try? makeWebloc(for: web) else { continue }
                restored.append(Item(id: record.id, url: local, addedAt: record.addedAt, sourceURL: web, isPinned: true))
                continue
            }
            var stale = false
            let url = record.bookmark.flatMap { try? URL(resolvingBookmarkData: $0, bookmarkDataIsStale: &stale) }
                ?? record.path.map { URL(fileURLWithPath: $0) }
            guard let url, fileManager.fileExists(atPath: url.path) else { continue }
            restored.append(Item(id: record.id, url: url, addedAt: record.addedAt, sourceURL: url, isPinned: true))
        }
        items = restored
        restored.forEach(loadThumbnail)
        // Saved again, so a file that's gone or moved is recorded as it is now.
        savePinned()
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
