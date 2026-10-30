import AppKit
import Observation

/// Another app that was playing when a newer one took over Now Playing, and may still be.
public struct MediaSource: Identifiable {
    public var id: String
    public var name: String
    public var icon: NSImage?
    public var info: NowPlayingInfo
    public var artwork: NSImage?
    public var accent: ColorMath.RGB
    /// When this snapshot was taken.
    public var since: Date
}

/// What is playing anywhere on the Mac, plus play/pause/skip/seek.
@MainActor
@Observable
public final class NowPlayingService {
    public private(set) var info: NowPlayingInfo?
    public private(set) var artwork: NSImage?
    public private(set) var accent: ColorMath.RGB = .white
    public private(set) var appIcon: NSImage?
    public private(set) var appName: String?
    /// False when the helper can't run on this Mac.
    public private(set) var isAvailable = true
    /// True for a while after playback pauses, so the activity doesn't vanish instantly.
    public private(set) var isLingering = false

    public var lingerDuration: TimeInterval = 30

    /// Which apps to show. Anything else playing is treated as if nothing were.
    public var appFilter: MediaAppFilter = .all {
        didSet {
            guard appFilter != oldValue else { return }
            applyFilterChange()
        }
    }

    /// Called with each app that reports playback, shown or not, so Settings can list it.
    @ObservationIgnored public var onAppSeen: ((String) -> Void)?

    /// Apps that were playing before the current one took over and are probably still going
    /// (macOS reports only one "now playing" app, so these are remembered here).
    public private(set) var otherSources: [MediaSource] = []
    /// Which app the music view shows: nil for the current one, or an id from `otherSources`.
    public var selectedSourceID: String?

    public var currentSourceID: String? { resolvedBundleIdentifier }

    public var selectedSource: MediaSource? {
        guard let selectedSourceID else { return nil }
        return otherSources.first { $0.id == selectedSourceID }
    }

    /// Whether Now Playing should appear as a live activity.
    public var isActivityVisible: Bool {
        guard let info, info.hasContent else { return false }
        return info.isPlaying || isLingering
    }

    @ObservationIgnored private let bridge = MediaBridgeClient()
    @ObservationIgnored private var lingerTask: Task<Void, Never>?
    @ObservationIgnored private var resolvedBundleIdentifier: String?
    /// After play/pause from the pill, the state we expect the player to report. A helper update
    /// sent before the player reacted would otherwise flip the button back for a moment.
    @ObservationIgnored private var expectedPlayState: (isPlaying: Bool, until: Date)?
    /// Artwork we asked the helper to resend, so a missing image triggers one request, not a loop.
    @ObservationIgnored private var requestedArtworkKey: String?
    @ObservationIgnored private var pruneTask: Task<Void, Never>?
    /// A source with no track length is kept this long after it stopped being current.
    static let otherSourceLimit: TimeInterval = 20 * 60

    public init() {
        bridge.onMessage = { [weak self] message in self?.handle(message) }
        bridge.onStateChange = { [weak self] state in
            self?.isAvailable = state != .unavailable
            if state == .unavailable {
                self?.apply(nil, artworkData: nil)
            }
        }
    }

    public func start() {
        bridge.start()
    }

    public func stop() {
        bridge.stop()
        lingerTask?.cancel()
        pruneTask?.cancel()
    }

    /// Brings another playing app to the front so it can be controlled there.
    public func open(_ source: MediaSource) {
        if let pid = source.info.processIdentifier, let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: Controls

    public func togglePlayPause() {
        guard var current = info else { return }
        let now = Date()
        current.elapsed = current.elapsed(at: now)
        current.sampledAt = now
        current.isPlaying.toggle()
        expectedPlayState = (current.isPlaying, now.addingTimeInterval(1.5))
        applyLocally(current)
        bridge.send("toggle")
    }

    public func nextTrack() {
        bridge.send("next")
    }

    public func previousTrack() {
        bridge.send("previous")
    }

    public func seek(to seconds: TimeInterval) {
        guard var current = info, let duration = current.duration else { return }
        let target = min(max(seconds, 0), duration)
        current.elapsed = target
        current.sampledAt = Date()
        applyLocally(current)
        bridge.send("seek \(target)")
    }

    public func openSourceApp() {
        if let pid = info?.processIdentifier, let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
            app.activate()
            return
        }
        guard
            let identifier = resolvedBundleIdentifier,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Updates

    func handle(_ parsed: ParsedBridgeMessage) {
        switch parsed.message {
        case .ready:
            isAvailable = true
        case .error:
            break
        case .nowPlaying(let newInfo, let artworkData):
            apply(newInfo, artworkData: artworkData, accent: parsed.artworkAccent)
        }
    }

    func apply(_ newInfo: NowPlayingInfo?, artworkData: Data?, accent newAccent: ColorMath.RGB? = nil, now: Date = Date()) {
        guard var newInfo else {
            info = nil
            artwork = nil
            accent = .white
            appIcon = nil
            appName = nil
            resolvedBundleIdentifier = nil
            endLinger()
            return
        }

        let identifier = Self.sourceIdentifier(for: newInfo)
        if let identifier { onAppSeen?(identifier) }
        guard appFilter.allows(identifier) else {
            // Only clear once: a hidden app keeps sending updates while it plays.
            if info != nil || isLingering { apply(nil, artworkData: nil) }
            expectedPlayState = nil
            return
        }

        if let expected = expectedPlayState {
            if now >= expected.until || newInfo.isPlaying == expected.isPlaying {
                expectedPlayState = nil
            } else if let local = info, local.title == newInfo.title {
                // Stale report from before the player reacted: keep the local playback state.
                newInfo.isPlaying = local.isPlaying
                newInfo.elapsed = local.elapsed
                newInfo.sampledAt = local.sampledAt
                newInfo.playbackRate = local.playbackRate
            }
        }

        let previous = snapshotOfCurrent(at: now)
        updateArtwork(for: newInfo, data: artworkData, accent: newAccent)
        updateSourceApp(identifier)
        trackOtherSources(previous: previous, now: now)

        let wasPlaying = info?.isPlaying ?? false
        info = newInfo
        if newInfo.isPlaying {
            endLinger()
        } else if wasPlaying {
            beginLinger()
        }
    }

    private func applyLocally(_ updated: NowPlayingInfo) {
        let wasPlaying = info?.isPlaying ?? false
        info = updated
        if updated.isPlaying {
            endLinger()
        } else if wasPlaying {
            beginLinger()
        }
    }

    private func updateArtwork(for newInfo: NowPlayingInfo, data: Data?, accent newAccent: ColorMath.RGB?) {
        if let data, let image = NSImage(data: data) {
            artwork = image
            accent = newAccent ?? ArtworkTint.accent(of: data)
            return
        }
        // No new bytes: keep the current image only if it belongs to this track.
        if newInfo.artworkKey == nil || newInfo.artworkKey != info?.artworkKey || artwork == nil {
            artwork = nil
            accent = .white
            // The track has art we never received (for example after a helper restart): ask once.
            if let key = newInfo.artworkKey, key != requestedArtworkKey {
                requestedArtworkKey = key
                bridge.send("refresh")
            }
        }
    }

    /// The app behind a report: the regular app owning the process when there is one, since
    /// browsers and some players report from a helper.
    private static func sourceIdentifier(for info: NowPlayingInfo) -> String? {
        var identifier = info.bundleIdentifier
        if let pid = info.processIdentifier, let app = NSRunningApplication(processIdentifier: pid) {
            if identifier == nil || app.activationPolicy == .regular {
                identifier = app.bundleIdentifier ?? identifier
            }
        }
        return identifier
    }

    private func updateSourceApp(_ identifier: String?) {
        guard identifier != resolvedBundleIdentifier else { return }
        resolvedBundleIdentifier = identifier
        guard let identifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            appIcon = nil
            appName = nil
            return
        }
        appIcon = NSWorkspace.shared.icon(forFile: url.path)
        appName = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    // MARK: Filter

    private func applyFilterChange() {
        otherSources.removeAll { !appFilter.allows($0.id) }
        if let selectedSourceID, !otherSources.contains(where: { $0.id == selectedSourceID }) {
            self.selectedSourceID = nil
        }
        if info != nil, !appFilter.allows(resolvedBundleIdentifier) {
            apply(nil, artworkData: nil)
        }
        // An app that's allowed now may already be playing: ask for the current state again.
        bridge.send("refresh")
    }

    // MARK: Other sources

    private func snapshotOfCurrent(at now: Date) -> MediaSource? {
        guard let info, info.hasContent, let id = resolvedBundleIdentifier else { return nil }
        return MediaSource(id: id, name: appName ?? id, icon: appIcon, info: info, artwork: artwork, accent: accent, since: now)
    }

    /// When another app takes over while the old one was playing, keep the old one as a source.
    private func trackOtherSources(previous: MediaSource?, now: Date) {
        let current = resolvedBundleIdentifier
        otherSources.removeAll { $0.id == current }
        if let previous, previous.id != current, previous.info.isPlaying {
            otherSources.removeAll { $0.id == previous.id }
            otherSources.insert(previous, at: 0)
        }
        if let selectedSourceID, !otherSources.contains(where: { $0.id == selectedSourceID }) {
            self.selectedSourceID = nil
        }
        schedulePrune()
    }

    /// Forgets sources whose app quit or whose track has run out.
    func pruneOtherSources(now: Date = Date()) {
        otherSources.removeAll { source in
            if NSRunningApplication.runningApplications(withBundleIdentifier: source.id).isEmpty { return true }
            if let duration = source.info.duration, let elapsed = source.info.elapsed(at: now) {
                return elapsed >= duration
            }
            return now.timeIntervalSince(source.since) > Self.otherSourceLimit
        }
        if let selectedSourceID, !otherSources.contains(where: { $0.id == selectedSourceID }) {
            self.selectedSourceID = nil
        }
    }

    private func schedulePrune() {
        pruneTask?.cancel()
        guard !otherSources.isEmpty else { return }
        pruneTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                self.pruneOtherSources()
                if self.otherSources.isEmpty { return }
            }
        }
    }

    private func beginLinger() {
        lingerTask?.cancel()
        isLingering = true
        let duration = lingerDuration
        lingerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.isLingering = false
        }
    }

    private func endLinger() {
        lingerTask?.cancel()
        lingerTask = nil
        isLingering = false
    }
}
