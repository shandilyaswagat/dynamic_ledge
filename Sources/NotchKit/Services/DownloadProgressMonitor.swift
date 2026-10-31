import AppKit
import Observation

/// Follows downloads into the Downloads folder while they're running. Safari, Chrome and other
/// browsers publish each download's progress for Finder (the bar on the file's icon); this
/// listens to the same reports. Nothing is read from the files themselves.
@MainActor
@Observable
public final class DownloadProgressMonitor {
    /// Downloads worth showing: running for a moment, so a small file that's done in an
    /// instant doesn't flash the notch.
    public private(set) var items: [DownloadProgressItem] = []

    public var summary: DownloadSummary { DownloadSummary(items) }

    @ObservationIgnored private let folder: URL
    @ObservationIgnored private var subscriber: Any?
    @ObservationIgnored private var tracked: [ObjectIdentifier: Tracked] = [:]
    @ObservationIgnored private var poll: Task<Void, Never>?

    /// How long a download must run before it shows.
    static let showAfter: TimeInterval = 1

    private struct Tracked {
        var progress: Progress
        var startedAt: Date
        var rate = DownloadRate()
    }

    public init(folder: URL? = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first) {
        self.folder = folder ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    public var isRunning: Bool { subscriber != nil }

    public func start() {
        guard subscriber == nil else { return }
        subscriber = Progress.addSubscriber(forFileURL: folder, withPublishingHandler: Self.handler(for: self))
    }

    public func stop() {
        if let subscriber { Progress.removeSubscriber(subscriber) }
        subscriber = nil
        tracked.removeAll()
        poll?.cancel()
        poll = nil
        if !items.isEmpty { items = [] }
    }

    /// Asks the browser to stop a download. Not every browser allows it.
    public func cancel(_ id: String) {
        tracked.values.first { Self.fileURL(of: $0.progress)?.path == id }?.progress.cancel()
    }

    public func canCancel(_ id: String) -> Bool {
        tracked.values.first { Self.fileURL(of: $0.progress)?.path == id }?.progress.isCancellable ?? false
    }

    /// Shows the file being downloaded in Finder.
    public func reveal(_ id: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: id)])
    }

    /// Publishing handlers arrive on a background queue; everything else happens on the main actor.
    nonisolated private static func handler(for monitor: DownloadProgressMonitor) -> @Sendable (Progress) -> Progress.UnpublishingHandler? {
        { [weak monitor] progress in
            let key = ObjectIdentifier(progress)
            Task { @MainActor in monitor?.track(progress, key: key) }
            return { Task { @MainActor in monitor?.untrack(key) } }
        }
    }

    /// A subscriber's copy of the progress keeps the file in its user info; `fileURL` comes back
    /// empty there.
    private static func fileURL(of progress: Progress) -> URL? {
        progress.fileURL ?? progress.userInfo[.fileURLKey] as? URL
    }

    private func track(_ progress: Progress, key: ObjectIdentifier) {
        // Only downloads: copies and other file work in the folder report here too.
        let operation = progress.fileOperationKind ?? progress.userInfo[.fileOperationKindKey] as? Progress.FileOperationKind
        guard tracked[key] == nil, operation == nil || operation == .downloading else { return }
        tracked[key] = Tracked(progress: progress, startedAt: Date())
        startPolling()
    }

    private func untrack(_ key: ObjectIdentifier) {
        tracked[key] = nil
        refresh()
    }

    /// Progress changes many times a second; reading it twice a second is plenty for the notch.
    private func startPolling() {
        guard poll == nil else { return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.refresh()
                if self.tracked.isEmpty {
                    self.poll = nil
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func refresh(now: Date = Date()) {
        var next: [DownloadProgressItem] = []
        for (key, var entry) in tracked {
            let progress = entry.progress
            if progress.isFinished || progress.isCancelled {
                tracked[key] = nil
                continue
            }
            guard let url = Self.fileURL(of: progress) else { continue }
            let completed = progress.completedUnitCount
            let total = progress.totalUnitCount
            entry.rate.add(bytes: completed, at: now)
            tracked[key] = entry
            guard now.timeIntervalSince(entry.startedAt) >= Self.showAfter else { continue }
            next.append(DownloadProgressItem(
                id: url.path,
                name: DownloadProgressItem.displayName(for: url),
                completed: completed,
                total: total,
                // Whole seconds, so the notch redraws when the text changes, not on every sample.
                secondsLeft: entry.rate.secondsLeft(completed: completed, total: total).map { $0.rounded() },
                startedAt: entry.startedAt
            ))
        }
        next.sort { $0.startedAt < $1.startedAt }
        // Only publish real changes, so the notch doesn't redraw for nothing.
        if next != items { items = next }
    }
}
