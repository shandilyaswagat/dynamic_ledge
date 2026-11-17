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
    /// True while a .zip, PDF or converted copy is being made, so it isn't started twice.
    public private(set) var isWorking = false

    public static let capacity = 30

    /// Pinned first (newest pin first), then the rest, newest first.
    public var ordered: [Item] {
        items.filter(\.isPinned) + items.filter { !$0.isPinned }
    }

    public var pinnedCount: Int { items.lazy.filter(\.isPinned).count }

    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let sessionFolder: URL
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let dropFolder: URL?
    @ObservationIgnored private var webDrops: [URL: URLSessionDataTask] = [:]
    @ObservationIgnored private let dropQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()
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
    public init(folder: URL? = nil, fileManager: FileManager = .default, defaults: UserDefaults? = .standard,
                dropFolder: URL? = nil) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.dropFolder = dropFolder ?? fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
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

    /// The source app writes promised files, including browser images, only after a drop.
    func receive(_ promises: [NSFilePromiseReceiver], fallback: [URL] = []) -> Bool {
        pruneMissing()
        let available = Self.capacity - items.count
        guard available > 0 else {
            statusMessage = "Tray full — remove an item to add another."
            return false
        }
        guard !promises.isEmpty, let staging = try? makeDropFolder() else {
            statusMessage = "Couldn’t prepare the dropped files."
            return false
        }
        statusMessage = "Receiving dropped files…"
        let canFallBack = promises.count == 1 && !fallback.isEmpty
        // AppKit requires all promises from one drag to share a destination.
        // Its completion runs on dropQueue; only the inner Task may touch main-actor state.
        for promise in promises.prefix(available) {
            promise.receivePromisedFiles(atDestination: staging, options: [:], operationQueue: dropQueue) { @Sendable [weak self] url, error in
                let failed = error != nil
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if failed {
                        if !canFallBack || !self.receiveWebLinks(fallback) {
                            self.statusMessage = "The source app couldn’t provide the dropped file."
                        }
                    } else {
                        self.finishDrop(url, from: staging)
                    }
                }
            }
        }
        return true
    }

    func saveDroppedImage(_ image: FileDropReader.Image) -> Bool {
        pruneMissing()
        guard items.count < Self.capacity else {
            statusMessage = "Tray full — remove an item to add another."
            return false
        }
        guard let staging = try? makeDropFolder() else {
            statusMessage = "Couldn’t prepare the dropped image."
            return false
        }
        let url = staging.appendingPathComponent(WebDropDownload.safeName(image.name + "." + image.ext))
        let data = image.data
        statusMessage = "Saving dropped file…"
        dropQueue.addOperation { [weak self] in
            let saved = (try? data.write(to: url, options: .atomic)) != nil
            Task { @MainActor [weak self] in
                defer { try? FileManager.default.removeItem(at: staging) }
                guard let self else { return }
                if saved { self.finishDrop(url, from: staging, quarantine: true) }
                else { self.statusMessage = "Couldn’t save the dropped image." }
            }
        }
        return true
    }

    /// Native file data takes priority. When a browser offers only an address, inspect its response
    /// to save a direct file or retain the address as a standard web shortcut.
    func receiveWebLinks(_ urls: [URL]) -> Bool {
        var accepted = false
        for url in urls where WebDropDownload.canFetch(url) {
            if webDrops[url] != nil { accepted = true; continue }
            if webDrops.count >= 2 {
                accepted = add([url]) > 0 || accepted
                continue
            }
            pruneMissing()
            guard items.count + webDrops.count < Self.capacity else {
                statusMessage = "Tray full — remove an item to add another."
                break
            }
            guard let staging = try? makeDropFolder() else {
                accepted = add([url]) > 0 || accepted
                continue
            }
            statusMessage = "Checking dropped link…"
            webDrops[url] = WebDropDownload.fetch(url, into: staging) { [weak self] result in
                Task { @MainActor [weak self] in
                    defer { try? FileManager.default.removeItem(at: staging) }
                    guard let self, self.webDrops.removeValue(forKey: url) != nil else { return }
                    switch result {
                    case .file(let file): self.finishDrop(file, from: staging, quarantine: true)
                    case .link: self.add([url])
                    case .failed:
                        if self.add([url]) > 0 {
                            self.statusMessage = "Couldn’t download the file. Saved its link instead."
                        }
                    }
                }
            }
            accepted = true
        }
        return accepted
    }

    private func makeDropFolder() throws -> URL {
        let folder = sessionFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        return folder
    }

    private func finishDrop(_ input: URL, from staging: URL, quarantine: Bool = false) {
        pruneMissing()
        guard items.count < Self.capacity else {
            statusMessage = "Tray full — remove an item to add another."
            return
        }
        do {
            guard input.isFileURL, input.deletingLastPathComponent().resolvingSymlinksInPath() == staging.resolvingSymlinksInPath(),
                  try input.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false,
                  let dropFolder else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            let target = TrayActions.unique(in: dropFolder, name: input.deletingPathExtension().lastPathComponent,
                                            extension: input.pathExtension, fileManager: fileManager)
            if quarantine {
                try (input as NSURL).setResourceValue([
                    "LSQuarantineType": "LSQuarantineTypeWebDownload",
                    "LSQuarantineAgentName": "Dynamic Ledge",
                ], forKey: .quarantinePropertiesKey)
            }
            try fileManager.moveItem(at: input, to: target)
            add([target])
        } catch {
            statusMessage = "Couldn’t save the dropped file to Downloads."
        }
    }

    /// Files on disk, in the order shown: what Zip and Merge PDF work on. Web links are left out.
    public var files: [URL] {
        ordered.filter { $0.sourceURL?.isFileURL != false }.map(\.url)
    }

    /// Merge PDF needs at least two PDFs or images.
    public var canMergePDF: Bool { files.filter(TrayActions.canMerge).count >= 2 }

    /// Compresses these files into one .zip next to the first, and adds it to the tray.
    public func zip(_ urls: [URL]) {
        run("Couldn't make the .zip.") { try TrayActions.zip(urls) }
    }

    /// Joins the tray's PDFs and images into one PDF next to the first, and adds it to the tray.
    public func mergePDFs() {
        let urls = files
        run("Couldn't make the PDF.") { try TrayActions.mergePDF(urls) }
    }

    /// Makes a file off the main thread, then adds it, or says what went wrong.
    private func run(_ failure: String, _ make: @escaping @Sendable () throws -> URL) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try make() } }.value
            isWorking = false
            switch result {
            case .success(let url): add([url])
            case .failure: statusMessage = failure
            }
        }
    }

    /// Saves a copy of an image in another format beside the original (or in Downloads), and adds
    /// the copy to the tray. The original is never changed. Large images convert off the main thread.
    public func convert(_ item: Item, to format: FileExportFormat) {
        let source = item.url
        run("Couldn't save the \(format.displayName) copy.") {
            try FileConverter.convertImage(at: source, to: format, destinationFolder: TrayActions.outputFolder(for: source))
        }
    }


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
        let downloads = webDrops.values
        webDrops.removeAll()
        for task in downloads { task.cancel() }
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

    /// What a drag or Copy hands over: the file itself, so Finder keeps its name and apps like
    /// Mail or WhatsApp receive the file. A web link hands over its address.
    public static func sharedURL(for item: Item) -> URL {
        if let source = item.sourceURL, !source.isFileURL { return source }
        return item.url
    }

    /// A drag of the file's location rather than a copy of its contents, which Finder saved
    /// under a made-up name.
    public static func dragProvider(for url: URL) -> NSItemProvider {
        NSItemProvider(object: url as NSURL)
    }

    /// Puts the item on the clipboard, as Finder's Copy does, ready to paste into another app.
    public func copy(_ item: Item, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects([Self.sharedURL(for: item) as NSURL])
    }

    public func copyPath(_ item: Item, to pasteboard: NSPasteboard = .general) {
        let url = Self.sharedURL(for: item)
        guard url.isFileURL else { return }
        pasteboard.clearContents()
        pasteboard.setString(url.path, forType: .string)
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
