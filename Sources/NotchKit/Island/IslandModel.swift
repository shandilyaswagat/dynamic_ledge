import AppKit
import Observation
import os

/// The single source of truth for what the pill shows and how it reacts.
@MainActor
@Observable
public final class IslandModel {
    public let settings: SettingsStore
    public let nowPlaying: NowPlayingService
    public let timer: TimerService
    public let calls: CallMonitor
    public let power: PowerMonitor
    public let audioRoute: AudioRouteMonitor
    public let tray: TrayStore
    public let calendar: CalendarService
    public let shortcuts: ShortcutsService
    public let levels: LevelMonitor
    public let clipboard: ClipboardMonitor
    public let lyrics = LyricsService()
    public let notes: NotesStore
    public let stopwatch: StopwatchService
    public let keepAwake = KeepAwakeService()
    public let microphone = MicrophoneMute()
    public let downloads: DownloadsWatcher
    public let downloadProgress = DownloadProgressMonitor()
    /// Permission requests from coding assistants.
    public let agents = AgentBridge()
    public let reminders = RemindersService()
    public let stats = StatsService()
    public let todos: TodoStore
    public let aiUsage: AIUsageService
    /// Speakers, headphones and displays the Mac can play through, for the music view's picker.
    public let audioOutput = AudioOutputService()
    /// Levels for the music bars, while Live music bars is on and something plays.
    public let spectrum = AudioSpectrumAnalyzer()
    /// A text field in the open nook has the keyboard (Notes or a new to-do in the elongated
    /// layout). The notch stays open while you type, even if the pointer wanders off.
    public var isTypingInNook = false
    /// Clipboard's search field is open, so the notch takes the keyboard for it.
    public var isSearchingClipboard = false
    /// The grid is picking the shortcuts beside Home (started by holding a tile). Ends when
    /// anything else opens or the notch closes.
    public var isEditingShortcuts = false
    /// Home's tiles are being rearranged (started by holding one). Ends with Done, or when
    /// anything else opens or the notch closes.
    public var isEditingHome = false
    public let hotKeys = HotKeys()
    public let updater = Updater()
    let usage = UsageReporter()
    let camera = CameraAccess()

    /// What the Timer panel starts, and the minutes picked on its ruler.
    public var timerPanelMode: TimerPanelMode = .timer
    public var timerPanelMinutes = 15
    public var focusPanelMinutes: Int

    /// The display you're using: where things open and the pointer is tracked. With "All
    /// displays" the other screens show the same activities but nothing opened.
    public var screen: ScreenMetrics = .sample
    public private(set) var activeDisplayID: UInt32 = 0
    public private(set) var alerts = AlertQueue()
    public private(set) var expandTarget: ExpandTarget? {
        // Stats reads more while its panel is open, and starts reading when it's opened from the
        // grid while something else is in the notch.
        didSet { if expandTarget != oldValue { syncStatsSampling() } }
    }
    public private(set) var preferredPrimary: ActivityKind?
    public private(set) var isHoveringPill = false
    public private(set) var isHoveringNotch = false
    public private(set) var isFileDragNear = false
    var isTextDrag = false
    private(set) var targetedTextAction: TextDropAction?
    private(set) var isCapturingWindow = false
    public var isDropTargeted = false
    /// Which half of the drop target the files are over.
    public private(set) var targetedZone: DropZone?
    /// True while the user drags a file out of the tray, so it isn't mistaken for a new drop.
    public var isDraggingFromTray = false
    /// A document window is moving, rather than a native pasteboard file drag.
    public var isDocumentWindowDrag = false

    public typealias DropZone = FileDropDestination
    /// True while the Appearance settings are open, so the pill shows for live preview.
    public var isPreviewing = false

    /// Asks the app to open the settings window.
    @ObservationIgnored public var onOpenSettings: (() -> Void)?
    /// Asks the app to open a specific Settings tab.
    @ObservationIgnored public var onOpenSettingsTab: ((SettingsWindowController.Tab) -> Void)?
    /// Asks the app to open Settings at Software Update, where updates are installed.
    @ObservationIgnored public var onOpenSoftwareUpdate: (() -> Void)?

    public func openSettings(_ tab: SettingsWindowController.Tab? = nil) {
        if let tab {
            onOpenSettingsTab?(tab)
        } else {
            onOpenSettings?()
        }
    }

    @ObservationIgnored private let alarm = AlarmSound()
    @ObservationIgnored private let audioTap = SystemAudioTap()
    @ObservationIgnored private var alertTask: Task<Void, Never>?
    @ObservationIgnored private var collapseTask: Task<Void, Never>?
    @ObservationIgnored private var hoverExpandTask: Task<Void, Never>?
    /// What the pending hover opens, so moving from the shape onto the bubble switches it.
    @ObservationIgnored private var hoverExpandTarget: ExpandTarget?
    /// Auto-collapse only starts once the pointer has been inside the expanded pill, so opening
    /// it from the menu bar doesn't collapse it while the pointer travels over.
    @ObservationIgnored private var pointerEnteredExpanded = false
    @ObservationIgnored private let log = Logger(subsystem: Log.subsystem, category: "island")

    public init(
        settings: SettingsStore,
        nowPlaying: NowPlayingService = NowPlayingService(),
        timer: TimerService? = nil,
        calls: CallMonitor = CallMonitor(),
        power: PowerMonitor = PowerMonitor(),
        audioRoute: AudioRouteMonitor = AudioRouteMonitor(),
        tray: TrayStore = TrayStore(),
        calendar: CalendarService = CalendarService(),
        shortcuts: ShortcutsService = ShortcutsService(),
        levels: LevelMonitor = LevelMonitor(),
        clipboard: ClipboardMonitor = ClipboardMonitor(),
        notes: NotesStore = NotesStore(),
        stopwatch: StopwatchService = StopwatchService(),
        downloads: DownloadsWatcher = DownloadsWatcher(),
        todos: TodoStore = TodoStore(),
        aiUsage: AIUsageService? = nil
    ) {
        self.settings = settings
        self.nowPlaying = nowPlaying
        let timer = timer ?? TimerService(defaults: settings.defaults)
        self.timer = timer
        self.calls = calls
        self.power = power
        self.audioRoute = audioRoute
        self.tray = tray
        self.calendar = calendar
        self.shortcuts = shortcuts
        self.levels = levels
        self.clipboard = clipboard
        self.notes = notes
        self.stopwatch = stopwatch
        self.downloads = downloads
        self.todos = todos
        self.aiUsage = aiUsage ?? AIUsageService(defaults: settings.defaults)
        focusPanelMinutes = settings.focusMinutes

        calendar.onReminder = { [weak self] event in
            guard let self, self.settings.calendarEnabled else { return }
            let minutes = max(0, Int((event.start.timeIntervalSinceNow / 60).rounded()))
            self.receive(.upcomingEvent(title: event.title, minutes: minutes))
        }
        shortcuts.onFinish = { [weak self] name, succeeded in
            self?.receive(.shortcut(name: name, succeeded: succeeded))
        }
        levels.onChange = { [weak self] kind, value, muted in
            guard let self else { return }
            // While an expanded view is open, it stays put; the system indicator still shows.
            guard self.expandTarget == nil else { return }
            self.receive(.level(kind, value: value, muted: muted))
        }

        timer.onFinish = { [weak self] in self?.timerDidFinish() }
        downloads.onFinished = { [weak self] url in self?.receive(.download(url)) }
        hotKeys.onPress = { [weak self] item in self?.open(item) }
        // The permission dialog closes the notch; reopen it on the calendar so the user sees it worked.
        calendar.onGranted = { [weak self] in self?.showTab(.calendar) }
        reminders.onGranted = { [weak self] in self?.showTab(.reminders) }
        updater.onAvailable = { [weak self] release in self?.receive(.updateAvailable(version: release.version.description)) }
        updater.onInstallStarting = { [weak self] automatically in
            guard let self, self.settings.sharesUsage else { return }
            self.usage.noteUpdateStarting(automatically: automatically)
        }
        updater.onInstallFailed = { [weak self] step, error in
            guard let self, self.settings.sharesUsage else { return }
            self.usage.noteUpdateFailed(step: step, error: error)
        }
        updater.isBusy = { [weak self] in
            guard let self else { return false }
            return !self.agents.pending.isEmpty || self.timer.isActive || self.stopwatch.isActive || self.calls.session != nil
        }
        power.onAlert = { [weak self] alert in self?.receive(alert) }
        audioRoute.onAlert = { [weak self] alert in self?.receive(alert) }
        nowPlaying.lingerDuration = settings.pausedMediaLinger
        nowPlaying.appFilter = settings.mediaAppFilter
        nowPlaying.onAppSeen = { [weak self] identifier in self?.settings.noteMediaApp(identifier) }
        nowPlaying.onTrackChange = { [weak self] info in
            self?.receive(.trackChanged(title: info.title, artist: info.artist))
        }
        agents.onChange = { [weak self] in self?.syncAgentAlert() }
        agents.onFinished = { [weak self] kind, project in
            guard let self, self.settings.agentFinishedAlerts else { return }
            self.receive(.agentFinished(agent: kind.displayName, project: project))
        }
        observeActivities()
        observeSettings()
        observeLyrics()
        // Set once, before the tap ever starts: its audio queue reads it.
        audioTap.onLevels = { [weak self] levels in
            Task { @MainActor [weak self] in
                guard let self, self.audioTap.isRunning else { return }
                self.spectrum.update(levels: levels)
            }
        }
        observeMusicBars()
    }

    public func startServices() {
        nowPlaying.start()
        calls.start()
        power.start()
        if settings.headphoneAlertsEnabled { audioRoute.start() }
        calendar.start()
        levels.start()
        audioOutput.start()
        clipboard.readsTextInImages = settings.clipboardReadsImages
        clipboard.excludedApps = settings.clipboardExcludedApps
        clipboard.keepsImages = settings.clipboardKeepsImages
        if settings.clipboardEnabled { clipboard.start() }
        syncMusicBars()
        syncAIUsageRefreshes()
        if settings.downloadsEnabled {
            downloads.start()
            downloadProgress.start()
        }
        agents.enabledKinds = settings.agentApprovals
        agents.watchesTranscripts = settings.agentWatchesTranscript
        if settings.agentApprovalsEnabled {
            agents.start()
            refreshAgentHooks()
        }
        microphone.start()
        if settings.remindersEnabled { reminders.start() }
        syncStatsSampling()
        if settings.keyboardShortcutsEnabled { hotKeys.register() }
        updater.installsAutomatically = settings.checksForUpdates && settings.installsUpdatesAutomatically
        if settings.checksForUpdates { updater.startAutomaticChecks() }
        if settings.sharesUsage { usage.start(isNewInstall: !settings.hasShownWelcome) }
        if !settings.hasShownWelcome {
            settings.hasShownWelcome = true
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.receive(.welcome)
            }
        }
    }

    public func stopServices() {
        nowPlaying.stop()
        calls.stop()
        power.stop()
        audioRoute.stop()
        calendar.stop()
        levels.stop()
        audioOutput.stop()
        clipboard.stop()
        downloads.stop()
        downloadProgress.stop()
        agents.stop()
        microphone.stop()
        reminders.stop()
        stats.stop()
        aiUsage.stopAutomaticRefreshes()
        audioTap.stop()
        spectrum.reset()
        hotKeys.unregister()
        updater.stopAutomaticChecks()
        usage.stop()
        keepAwake.turnOff()
        notes.save()
        alarm.stop()
    }

    // MARK: Derived state

    public var engine: LayoutEngine {
        engine(for: screen)
    }

    public func engine(for metrics: ScreenMetrics) -> LayoutEngine {
        LayoutEngine(screen: metrics, appearance: settings.appearance)
    }

    /// Makes a display the one you're using. Ignored while something is open elsewhere, so a
    /// view never jumps screens under you; it switches once that closes.
    @discardableResult
    public func activate(display id: UInt32, metrics: ScreenMetrics) -> Bool {
        if id == activeDisplayID {
            if screen != metrics { screen = metrics }
            return true
        }
        guard expandTarget == nil, !isFileDragNear, !isDropTargeted, !isDocumentWindowDrag else { return false }
        cancelHoverExpand()
        setHovering(pill: false, notch: false)
        activeDisplayID = id
        screen = metrics
        return true
    }

    /// The only display there is (every mode except "All displays"): always the one in use.
    public func useOnly(display id: UInt32, metrics: ScreenMetrics) {
        if activeDisplayID != id {
            cancelHoverExpand()
            setHovering(pill: false, notch: false)
            activeDisplayID = id
        }
        if screen != metrics { screen = metrics }
    }

    /// The edge can be far from the notch. Wait for the pointer to reach Home before
    /// applying the normal pointer-exit collapse behavior.
    @discardableResult
    func openHomeFromEdge(on displayID: UInt32, metrics: ScreenMetrics) -> Bool {
        guard expandTarget == nil, !presentation.isExpandedFamily,
              !isFileDragNear, !isDropTargeted, !isDocumentWindowDrag,
              activate(display: displayID, metrics: metrics) else { return false }
        pointerMoved(to: nil)
        expand(.home)
        return true
    }

    /// What a display shows: everything on the one you're using; on the others the same
    /// activities and alerts, but nothing opened, dragged or hovered.
    public func presentation(onDisplay id: UInt32) -> IslandPresentation {
        if id == activeDisplayID { return presentation }
        return PresentationResolver.resolve(PresentationInput(
            activeActivities: activeActivities,
            preferredPrimary: preferredPrimary,
            alert: alerts.current,
            showWhenIdle: settings.showWhenIdle,
            isPreviewing: isPreviewing
        ))
    }

    public func layout(onDisplay id: UInt32, metrics: ScreenMetrics) -> IslandLayout {
        if id == activeDisplayID { return layout }
        return engine(for: metrics).layout(for: presentation(onDisplay: id), home: homeContent, hovering: false)
    }

    public var activeActivities: Set<ActivityKind> {
        var active = Set<ActivityKind>()
        if settings.callsEnabled, calls.session != nil { active.insert(.call) }
        if settings.timerEnabled, timer.isActive { active.insert(.timer) }
        if settings.timerEnabled, stopwatch.isActive { active.insert(.stopwatch) }
        if settings.nowPlayingEnabled, nowPlaying.isActivityVisible,
           !settings.nowPlayingOnHoverOnly || isHoveringPill || isHoveringNotch || expandTarget != nil {
            active.insert(.nowPlaying)
        }
        if settings.downloadsEnabled, !downloadProgress.items.isEmpty { active.insert(.download) }
        // Stats fills idle space. AI usage does too, and also stays beside music or video.
        let idle = active.isEmpty
        if idle, settings.statsEnabled { active.insert(.stats) }
        if settings.aiUsageLive, idle || active == [.nowPlaying] { active.insert(.aiUsage) }
        return active
    }

    public var presentation: IslandPresentation {
        PresentationResolver.resolve(PresentationInput(
            activeActivities: activeActivities,
            preferredPrimary: preferredPrimary,
            alert: alerts.current,
            expandTarget: expandTarget,
            isFileDragNear: (acceptsFileDrops || isTextDrag) && isFileDragNear,
            isDropTargeted: (acceptsFileDrops || isTextDrag) && isDropTargeted,
            showWhenIdle: settings.showWhenIdle,
            isHoveringNotch: isHoveringNotch,
            isPreviewing: isPreviewing
        ))
    }

    /// What the Lock Screen shows while the Mac is locked, if anything.
    public var lockScreenContent: LockScreenContent? {
        LockScreenContent.choose(
            timer: settings.timerEnabled && timer.isActive,
            music: homeHasMedia,
            stopwatch: settings.timerEnabled && stopwatch.isActive,
            power: power.snapshot
        )
    }

    /// The music view shows a line of lyrics: the song has timed lyrics, and the view is on it
    /// rather than on another app that's playing.
    public var showsLyrics: Bool {
        settings.nowPlayingEnabled && settings.lyricsEnabled && lyrics.current != nil && nowPlaying.selectedSource == nil
    }

    var lyricTimingAdjustment: TimeInterval {
        let milliseconds = audioOutput.currentDevice?.isBluetooth == true
            ? settings.bluetoothLyricOffset : settings.lyricOffset
        return TimeInterval(milliseconds) / 1000
    }

    public var homeHasMedia: Bool {
        settings.nowPlayingEnabled && nowPlaying.info?.hasContent == true
    }

    /// Files can be dropped on the notch when at least one destination is on.
    public var acceptsFileDrops: Bool {
        settings.airDropEnabled || settings.trayEnabled
    }

    /// The calendar row shows the next event, or a button to connect the calendar.
    public var showsCalendarRow: Bool {
        // Always shown when switched on, so there's a way to connect or fix access from Home.
        settings.calendarEnabled
    }

    public var favoriteShortcuts: [String] {
        guard settings.shortcutsEnabled else { return [] }
        return settings.favoriteShortcuts
    }

    public var homeContent: HomeContent {
        HomeContent(
            hasMedia: homeHasMedia,
            hasEvent: showsCalendarRow,
            hasTimer: settings.timerEnabled,
            hasShortcuts: !favoriteShortcuts.isEmpty,
            hasMediaSwitcher: !nowPlaying.otherSources.isEmpty,
            hasLyrics: showsLyrics,
            hasClipboardSearch: isSearchingClipboard,
            hasLiveTile: !homeLiveItems.isEmpty,
            isEditingHome: isEditingHome
        )
    }

    // MARK: Home grid

    /// Home's tiles whose feature is switched on, in order. One switched off in Settings is
    /// hidden, and comes back when it's switched on again.
    public var homeTiles: [HomeTile] {
        settings.homeTiles.filter { isAvailable($0.item) }
    }

    var elongatedHomeTiles: [HomeTile] {
        settings.elongatedHomeTiles.filter { tile in
            guard canAddElongatedTile(tile.item) else { return false }
            if isEditingHome { return true }
            switch tile.item {
            case .nowPlaying: return homeHasMedia
            case .aiUsage: return !aiUsage.visibleUsages(selected: settings.selectedAIProviders).isEmpty
            default: return true
            }
        }
    }

    /// Features that can be added to Home while editing: switched on and not there yet.
    public var addableHomeItems: [HomeTileItem] {
        if settings.appearance.nookLayout == .elongated {
            let saved = Set(settings.elongatedHomeTiles.map(\.item))
            return HomeTileItem.allCases.filter { canAddElongatedTile($0) && !saved.contains($0) }
        }
        let shown = Set(settings.homeTiles.map(\.item))
        return HomeTileItem.standardItems.filter { isAvailable($0) && !shown.contains($0) }
    }

    private func canAddElongatedTile(_ item: HomeTileItem) -> Bool {
        switch item {
        case .nowPlaying: settings.nowPlayingEnabled
        case .reminders: true // Elongated has the local to-do list.
        case .stats: settings.statsEnabled
        case .aiUsage: settings.aiUsageLive && settings.aiUsageShowHomeWidget
        default: isAvailable(item)
        }
    }

    /// A tile's feature is switched on (Shortcuts: in Settings › Home).
    private func isAvailable(_ item: HomeTileItem) -> Bool {
        guard let feature = item.launcherItem else { return settings.shortcutsEnabled }
        return launcherItems.contains(feature)
    }

    /// A tile was clicked: its feature opens, or Shortcuts runs the first favourite (with none
    /// picked yet, Settings opens to pick some).
    public func openTile(_ item: HomeTileItem) {
        if let feature = item.launcherItem {
            open(feature)
        } else if let first = favoriteShortcuts.first {
            shortcuts.run(first)
        } else {
            collapse()
            openSettings(.shortcuts)
        }
    }

    /// Whether a tile's thing is on right now.
    public func isTileLive(_ item: HomeTileItem) -> Bool {
        item.launcherItem.map(isLive) ?? false
    }

    /// Live activities shown beside Home's grid, two at most: a call, music, then a running
    /// clock, Stats or AI usage whose tile isn't on Home. Paused music comes last.
    var homeLiveItems: [HomeSection.LiveItem] {
        let active = activeActivities
        let tiles = Set(homeTiles.compactMap(\.item.launcherItem))
        var live: [HomeSection.LiveItem] = []
        if active.contains(.call) { live.append(.call) }
        let musicIsLive = active.contains(.nowPlaying)
        if homeHasMedia, musicIsLive { live.append(.music) }
        if active.contains(.timer), !tiles.contains(.timer) { live.append(.timer) }
        if active.contains(.stopwatch), !tiles.contains(.stopwatch) { live.append(.stopwatch) }
        if active.contains(.stats), !tiles.contains(.stats) { live.append(.stats) }
        if active.contains(.aiUsage), !tiles.contains(.aiUsage) { live.append(.aiUsage) }
        if homeHasMedia, !musicIsLive { live.append(.music) }
        return Array(live.prefix(HomeSection.maximumLive))
    }

    public func startEditingHome() {
        guard !isEditingHome else { return }
        isEditingHome = true
        Haptics.perform(enabled: settings.hapticsEnabled)
    }

    public func addHomeTile(_ item: HomeTileItem) {
        let elongated = settings.appearance.nookLayout == .elongated
        guard elongated ? canAddElongatedTile(item) : item != .nowPlaying && isAvailable(item) else { return }
        editHomeGrid {
            if $0.add(item), elongated { $0.resize(item, to: .wide) }
        }
    }

    public func removeHomeTile(_ item: HomeTileItem) {
        editHomeGrid { $0.remove(item) }
    }

    public func resizeHomeTile(_ item: HomeTileItem, to size: HomeTileSize) {
        editHomeGrid { $0.resize(item, to: size) }
    }

    public func moveHomeTile(_ item: HomeTileItem, to target: HomeTileItem) {
        editHomeGrid { $0.move(item, to: target) }
    }

    /// Back to the tiles Home starts with.
    public func resetHomeTiles() {
        let layout = settings.appearance.nookLayout
        editHomeGrid {
            $0 = HomeGrid(tiles: layout == .elongated ? HomeGrid.defaultElongatedTiles : HomeGrid.defaultTiles, layout: layout)
        }
    }

    private func editHomeGrid(_ update: (inout HomeGrid) -> Void) {
        let layout = settings.appearance.nookLayout
        let elongated = layout == .elongated
        let saved = elongated ? settings.elongatedHomeTiles : settings.homeTiles
        var grid = HomeGrid(tiles: saved, layout: layout)
        update(&grid)
        guard grid.tiles != saved else { return }
        if elongated { settings.elongatedHomeTiles = grid.tiles }
        else { settings.homeTiles = grid.tiles }
        syncStatsSampling()
    }

    /// The saved shortcuts beside Home whose feature is switched on, in order. One switched off
    /// in Settings is hidden, and comes back when it's switched on again.
    public var featureShortcuts: [LauncherItem] {
        let available = launcherItems
        return settings.featureShortcuts.filter(available.contains)
    }

    /// Adds a shortcut. When every slot is taken but some belong to switched-off features, the
    /// hidden one makes room, since the user can only see and count the visible ones.
    @discardableResult
    public func addFeatureShortcut(_ item: LauncherItem) -> Bool {
        guard featureShortcuts.count < SettingsStore.maximumFeatureShortcuts else { return false }
        var saved = settings.featureShortcuts
        if saved.count >= SettingsStore.maximumFeatureShortcuts, let hidden = saved.lastIndex(where: { !launcherItems.contains($0) }) {
            saved.remove(at: hidden)
            settings.featureShortcuts = saved
        }
        return settings.addFeatureShortcut(item)
    }

    /// Opens Home on the very first launch, so a new user sees the app start, and closes it
    /// again after a few seconds unless they've moved onto it.
    public func showHomeBriefly(for seconds: Double = 6) {
        showTab(.home)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, self.expandTarget == .home, !self.pointerEnteredExpanded, !self.isHoveringPill else { return }
            self.collapse()
        }
    }

    /// Tiles in the launcher grid: everything that's switched on.
    public var launcherItems: [LauncherItem] {
        LauncherItem.allCases.filter { item in
            switch item {
            case .nowPlaying: settings.nowPlayingEnabled
            case .timer, .stopwatch: settings.timerEnabled
            case .calendar: settings.calendarEnabled
            case .reminders: settings.remindersEnabled
            case .clipboard: settings.clipboardEnabled
            case .files: settings.trayEnabled
            case .scratchpad: settings.notesEnabled
            case .mirror: settings.mirrorEnabled
            case .keepAwake, .stats: true
            case .aiUsage: settings.aiUsageEnabled
            }
        }
    }

    /// Whether a tile's thing is on right now (music playing, a timer running, kept awake).
    public func isLive(_ item: LauncherItem) -> Bool {
        switch item {
        case .nowPlaying: nowPlaying.info?.isPlaying == true
        case .timer: timer.isActive
        case .stopwatch: stopwatch.isActive
        case .keepAwake: keepAwake.isOn
        case .stats: settings.statsEnabled
        case .aiUsage: settings.aiUsageLive
        default: false
        }
    }

    /// A tile was clicked or its shortcut pressed.
    public func open(_ item: LauncherItem) {
        switch item {
        case .nowPlaying:
            if activeActivities.contains(.nowPlaying) { expand(.activity(.nowPlaying)) } else { showTab(.home) }
        case .timer:
            if timer.isActive {
                expand(.activity(.timer))
            } else {
                timerPanelMode = .timer
                showTab(.timers)
            }
        case .stopwatch:
            if stopwatch.isActive {
                expand(.activity(.stopwatch))
            } else {
                timerPanelMode = .stopwatch
                showTab(.timers)
            }
        case .calendar: showTab(.calendar)
        case .reminders: showTab(.reminders)
        case .clipboard: showTab(.clipboard)
        case .files: showTab(.tray)
        case .scratchpad: showTab(.notes)
        case .mirror: showTab(.mirror)
        case .keepAwake:
            toggleKeepAwake()
            Haptics.perform(enabled: settings.hapticsEnabled)
        case .stats:
            // A switch, like Keep Awake: memory and CPU beside the camera, on or off.
            settings.statsEnabled.toggle()
            syncStatsSampling()
            Haptics.perform(enabled: settings.hapticsEnabled)
        case .aiUsage:
            // Match Stats: toggle the compact readout and its automatic checks.
            settings.aiUsageInNotch.toggle()
            syncAIUsageRefreshes()
            Haptics.perform(enabled: settings.hapticsEnabled)
        }
    }

    func toggleKeepAwake() {
        let minutes = settings.keepAwakeMinutes
        keepAwake.toggle(for: minutes > 0 ? TimeInterval(minutes) * 60 : nil)
    }

    public var layout: IslandLayout {
        engine.layout(for: presentation, home: homeContent, hovering: isHoveringPill)
    }

    // MARK: Pointer

    /// Updates hover state for a pointer position in window coordinates. Returns whether the
    /// window should receive mouse events there.
    @discardableResult
    public func pointerMoved(to point: CGPoint?) -> Bool {
        let current = presentation
        let engine = engine
        let atVirtualEdge = point.map(engine.touchesVirtualNotchEdge) ?? false
        let inside: Bool
        var onBubble = false
        if case .hidden(let peek) = current {
            let insideNotch = point.map(engine.notchHoverRect.contains) ?? false
            inside = engine.isVirtualNotch ? atVirtualEdge || (peek && insideNotch) : insideNotch
        } else {
            let resting = engine.layout(for: current, home: homeContent, hovering: false)
            inside = point.map { point in
                engine.interactiveRects(for: current, layout: resting).contains { $0.contains(point) }
            } ?? false
            if inside, let point, case .compact(_, .some) = current {
                onBubble = engine.bubbleHitRect(resting).contains(point)
            }
        }

        if case .hidden = current {
            setHovering(pill: false, notch: inside)
        } else {
            setHovering(pill: inside || atVirtualEdge, notch: false)
        }

        if current.isExpandedFamily {
            if inside || atVirtualEdge {
                pointerEnteredExpanded = true
                collapseTask?.cancel()
                collapseTask = nil
            } else if pointerEnteredExpanded, settings.collapseOnPointerExit, expandTarget != nil, expandTarget != .notes {
                scheduleCollapse()
            }
        }

        let canHoverOpen = settings.notchOpenMode == .hover && (engine.isVirtualNotch ? atVirtualEdge : inside)
        // Edge entry can reveal a compact activity that is configured to show only on hover.
        let hoverPresentation = atVirtualEdge && current.isHidden ? presentation : current
        if canHoverOpen, case .compact(let primary, let secondary) = hoverPresentation {
            // Like any activity, hovering Stats opens Stats; hovering the bubble opens its own.
            scheduleHoverExpand(.activity(onBubble ? secondary ?? primary : primary))
        } else if canHoverOpen, current == .idle || current.isHidden {
            // The tucked-away notch, or the resting pill (Show when idle, or while previewing a
            // size in Settings), opens Home.
            scheduleHoverExpand(.home)
        } else {
            cancelHoverExpand()
        }

        if engine.isVirtualNotch, current.isHidden, inside, let point {
            let revealed = engine.layout(for: .hidden(peek: true), home: homeContent, hovering: false)
            return revealed.pill.contains(point) || isFileDragNear
        }
        return inside || isFileDragNear
    }

    private func setHovering(pill: Bool, notch: Bool) {
        if isHoveringPill != pill { isHoveringPill = pill }
        if isHoveringNotch != notch { isHoveringNotch = notch }
    }

    /// A click anywhere outside the pill.
    public func outsideClick() {
        if expandTarget != nil {
            collapse()
        }
    }

    // MARK: Taps and gestures

    public func tapPill() {
        switch presentation {
        case .hidden, .idle:
            guard settings.notchOpenMode.edge == nil else { return }
            expand(.home)
        case .compact(let primary, _):
            guard settings.notchOpenMode.edge == nil else { return }
            expand(.activity(primary))
        case .alert(.download(let url)):
            NSWorkspace.shared.activateFileViewerSelecting([url])
            dismissAlert()
        case .alert(.agentRequest):
            // Needs an answer from its buttons; a stray click mustn't count as one.
            break
        case .alert(.updateAvailable):
            dismissAlert()
            onOpenSoftwareUpdate?()
        case .alert(let alert) where alert != .timerFinished:
            dismissAlert()
        default:
            break
        }
    }

    public func tapBubble() {
        guard settings.notchOpenMode.edge == nil else { return }
        if case .compact(_, let secondary?) = presentation {
            expand(.activity(secondary))
        }
    }

    public func expand(_ target: ExpandTarget) {
        // Stats and AI usage open as panels in the nook, with the grid and Home a click away.
        let target: ExpandTarget = switch target {
        case .activity(.stats): .nook(.stats)
        case .activity(.aiUsage): .nook(.aiUsage)
        default: target
        }
        cancelHoverExpand()
        collapseTask?.cancel()
        collapseTask = nil
        pointerEnteredExpanded = isHoveringPill
        if target != .home { isEditingHome = false }
        if expandTarget != target {
            expandTarget = target
            Haptics.perform(enabled: settings.hapticsEnabled)
        }
    }

    public func collapse() {
        collapseTask?.cancel()
        collapseTask = nil
        pointerEnteredExpanded = false
        guard expandTarget != nil else { return }
        isTypingInNook = false
        isSearchingClipboard = false
        isEditingShortcuts = false
        isEditingHome = false
        if expandTarget == .notes { notes.save() }
        expandTarget = nil
        syncStatsSampling()
        if !setAsideAgentRequests.isEmpty {
            // Back to the requests that were set aside to use Home.
            setAsideAgentRequests.removeAll()
            syncAgentAlert()
        } else {
            pumpAlerts()
        }
    }

    /// Two-finger swipe: bring the next activity to the front.
    public func cyclePrimary(forward: Bool) {
        let active = activeActivities
        let current = PresentationResolver.ordered(active, preferred: preferredPrimary).first
        guard let next = PresentationResolver.nextPrimary(active, current: current, forward: forward) else { return }
        preferredPrimary = next
        Haptics.perform(enabled: settings.hapticsEnabled)
    }

    private func scheduleCollapse() {
        guard collapseTask == nil else { return }
        let delay = settings.collapseDelay
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.collapseTask = nil
            if self.settings.collapseOnPointerExit, !self.isHoveringPill, !self.isTypingInNook {
                self.collapse()
            }
        }
    }

    private func cancelHoverExpand() {
        hoverExpandTask?.cancel()
        hoverExpandTask = nil
        hoverExpandTarget = nil
    }

    private func scheduleHoverExpand(_ target: ExpandTarget) {
        if hoverExpandTask != nil {
            guard hoverExpandTarget != target else { return }
            cancelHoverExpand()
        }
        hoverExpandTarget = target
        hoverExpandTask = Task { [weak self] in
            let ms = Int(((self?.settings.hoverDelay ?? 0.2) * 1000).rounded())
            try? await Task.sleep(for: .milliseconds(max(50, ms)))
            guard !Task.isCancelled, let self else { return }
            self.hoverExpandTask = nil
            self.hoverExpandTarget = nil
            guard self.settings.notchOpenMode == .hover else { return }
            switch (target, self.presentation) {
            case (.activity(let kind), .compact(let primary, let secondary))
                where (self.isHoveringPill || (self.engine.isVirtualNotch && self.isHoveringNotch))
                    && (primary == kind || secondary == kind):
                self.expand(target)
            case (.home, .hidden) where self.isHoveringNotch, (.home, .idle) where self.isHoveringPill:
                self.expand(.home)
                self.pointerEnteredExpanded = true
            default:
                break
            }
        }
    }

    // MARK: Alerts

    public func receive(_ alert: IslandAlert) {
        guard isEnabled(alert) else { return }
        if alerts.enqueue(alert, now: Date()) {
            scheduleAlertExpiry()
        }
        pumpAlerts()
    }

    public func dismissAlert() {
        if alerts.current == .timerFinished {
            stopTimerAlarm()
            return
        }
        if case .agentRequest(let request) = alerts.current {
            // Closing it sends the question back to the assistant's own window.
            agents.answer(request.id, .ask)
            return
        }
        alerts.dismissCurrent()
        pumpAlerts()
        scheduleAlertExpiry()
    }

    private func isEnabled(_ alert: IslandAlert) -> Bool {
        switch alert {
        case .charging, .batteryFull: settings.chargingAlertsEnabled
        case .lowBattery: settings.lowBatteryAlertsEnabled
        case .headphones: settings.headphoneAlertsEnabled
        case .trackChanged: settings.nowPlayingEnabled && settings.trackChangeAlertsEnabled
        case .level(.volume, _, _): settings.volumeAlertsEnabled
        case .level(.brightness, _, _): settings.brightnessAlertsEnabled
        case .upcomingEvent: settings.calendarEnabled
        case .download: settings.downloadsEnabled
        case .updateAvailable: true
        case .timerFinished, .welcome, .shortcut: true
        // The bridge's list follows the settings.
        case .agentRequest(let request): agents.enabledKinds.contains(request.kind)
        case .agentFinished: settings.agentFinishedAlerts
        }
    }

    /// Requests set aside to use Home. They keep waiting (and can still be answered in the
    /// assistant's window) and come back when the notch closes.
    private var setAsideAgentRequests: Set<UUID> = []

    /// Leaves the request on show unanswered and opens Home.
    public func setAsideAgentRequest() {
        guard case .agentRequest(let request) = alerts.current else { return }
        setAsideAgentRequests.insert(request.id)
        alerts.dismissCurrent()
        scheduleAlertExpiry()
        expand(.home)
    }

    /// Answers the request on show.
    public func answerAgent(_ decision: AgentDecision) {
        guard case .agentRequest(let request) = alerts.current else { return }
        agents.answer(request.id, decision)
    }

    /// Keeps the notch showing the oldest waiting request, one at a time.
    private func syncAgentAlert() {
        setAsideAgentRequests.formIntersection(agents.pending.map(\.id))
        let head = agents.pending.first { !setAsideAgentRequests.contains($0.id) }
        if case .agentRequest(let shown) = alerts.current, shown.id != head?.id {
            alerts.dismissCurrent()
            scheduleAlertExpiry()
        }
        if let head, alerts.current != .agentRequest(head), !alerts.pending.contains(.agentRequest(head)) {
            alerts.removeAll(of: .agent)
            receive(.agentRequest(head))
        } else {
            pumpAlerts()
        }
    }

    private func pumpAlerts() {
        if alerts.promote(now: Date(), allowNonUrgent: expandTarget == nil) {
            scheduleAlertExpiry()
        }
    }

    private func scheduleAlertExpiry() {
        alertTask?.cancel()
        alertTask = nil
        guard let expiry = alerts.expiry else { return }
        let delay = max(0, expiry.timeIntervalSinceNow)
        alertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            let wasTimer = self.alerts.current == .timerFinished
            let agentRequest: AgentRequest? = if case .agentRequest(let request) = self.alerts.current { request } else { nil }
            let removed = self.alerts.expire(now: Date())
            self.alertTask = nil
            if removed {
                if let agentRequest { self.agents.answer(agentRequest.id, .ask) }
                if wasTimer {
                    // Nobody stopped it: clear the finished timer along with its alert.
                    self.alarm.stop()
                    self.timer.cancel()
                }
                self.pumpAlerts()
            }
            // Covers a wake-up before the deadline (for example after a clock change).
            if self.alertTask == nil {
                self.scheduleAlertExpiry()
            }
        }
    }

    // MARK: Timer

    public func startTimer(_ duration: TimeInterval) {
        stopAlarmIfNeeded()
        timer.start(duration: duration)
        collapse()
    }

    /// Starts a focus session, or the break after one. Lengths come from Settings unless given.
    public func startSession(_ mode: TimerMode, minutes chosen: Int? = nil) {
        let minutes = chosen ?? {
            switch mode {
            case .focus: settings.focusMinutes
            case .rest: timer.shouldOfferLongBreak ? settings.longBreakMinutes : settings.breakMinutes
            case .plain: 0
            }
        }()
        guard minutes > 0 else { return }
        alarm.stop()
        alerts.removeAll(of: .timer)
        timer.start(duration: TimeInterval(minutes * 60), mode: mode)
        collapse()
        pumpAlerts()
        scheduleAlertExpiry()
    }

    public func cancelTimer() {
        timer.cancel()
    }

    /// "Start" in the Timer panel.
    public func startFromPanel() {
        switch timerPanelMode {
        case .timer: startTimer(TimeInterval(timerPanelMinutes * 60))
        case .focus: startSession(.focus, minutes: focusPanelMinutes)
        case .stopwatch:
            stopwatch.reset()
            stopwatch.start()
            collapse()
        }
    }

    public func resetStopwatch() {
        stopwatch.reset()
    }

    // MARK: Gestures

    /// Two fingers pulled down on the notch open it; pushed up close it.
    public func pull(open: Bool) {
        if open {
            switch presentation {
            case .hidden, .idle: expand(.home)
            case .compact(let primary, _): expand(.activity(primary))
            default: break
            }
        } else if expandTarget != nil {
            collapse()
        }
    }

    /// A sideways swipe skips songs when music is in front, and otherwise swaps activities.
    public func swipe(forward: Bool) {
        let front: ActivityKind? = switch presentation {
        case .compact(let primary, _): primary
        case .expanded(let kind): kind
        default: nil
        }
        if front == .nowPlaying {
            if forward { nowPlaying.nextTrack() } else { nowPlaying.previousTrack() }
            Haptics.perform(enabled: settings.hapticsEnabled)
        } else if case .compact = presentation {
            cyclePrimary(forward: forward)
        }
    }

    private func timerDidFinish() {
        receive(.timerFinished)
        if settings.timerSound {
            alarm.start()
        }
    }

    /// "Stop" on the timer-done alert.
    public func stopTimerAlarm() {
        alarm.stop()
        timer.cancel()
        alerts.removeAll(of: .timer)
        pumpAlerts()
        scheduleAlertExpiry()
    }

    /// "Repeat" on the timer-done alert.
    public func repeatTimer() {
        alarm.stop()
        alerts.removeAll(of: .timer)
        timer.repeatLast()
        pumpAlerts()
        scheduleAlertExpiry()
    }

    private func stopAlarmIfNeeded() {
        if alerts.current == .timerFinished || alerts.pending.contains(.timerFinished) {
            alarm.stop()
            alerts.removeAll(of: .timer)
            pumpAlerts()
        }
    }

    // MARK: AirDrop

    public func fileDragChanged(isDragging: Bool, at point: CGPoint?) {
        if !isDragging {
            isTextDrag = false
            targetedTextAction = nil
            isDraggingFromTray = false
        }
        let near = (acceptsFileDrops || isTextDrag) && isDragging && !isDraggingFromTray
            && (point.map { engine.dropZone.contains($0) } ?? false)
        if near != isFileDragNear {
            isFileDragNear = near
        }
        if isDragging, isTextDrag {
            targetedTextAction = point.flatMap { TextDropAction.destination(at: $0, content: layout.content, notes: settings.notesEnabled) }
            isDropTargeted = targetedTextAction != nil
        }
        if !isDragging, isDropTargeted {
            setTargeted(nil, false)
        }
    }

    /// Called by each half of the drop target as files move over it.
    public func setTargeted(_ zone: DropZone?, _ targeted: Bool) {
        if targeted {
            targetedZone = zone
        } else if zone == nil || targetedZone == zone {
            targetedZone = nil
        }
        let any = targetedZone != nil
        if isDropTargeted != any { isDropTargeted = any }
    }

    @discardableResult
    func acceptDrop(_ pasteboard: NSPasteboard, into destination: DropZone) -> Bool {
        let urls = FileDropReader.urls(from: pasteboard)
        if destination == .tray, settings.trayEnabled {
            if urls.contains(where: \.isFileURL) { return acceptDrop(urls, into: destination) }
            if let file = FileDropReader.promisedBytes(from: pasteboard, source: urls.first)
                ?? FileDropReader.image(from: pasteboard, source: urls.first) {
                let saved = tray.saveDroppedImage(file)
                expand(.tray)
                pointerEnteredExpanded = true
                return saved
            }
            let promises = FileDropReader.promises(from: pasteboard)
            if !promises.isEmpty {
                let accepted = tray.receive(promises, fallback: urls)
                expand(.tray)
                pointerEnteredExpanded = true
                return accepted
            }
            if tray.receiveWebLinks(urls) {
                expand(.tray)
                pointerEnteredExpanded = true
                return true
            }
        }
        return acceptDrop(urls, into: destination)
    }

    @discardableResult
    public func acceptDrop(_ urls: [URL], into destination: DropZone) -> Bool {
        let supported = urls.filter(DropPolicy.isSupported)
        guard !supported.isEmpty else { return false }
        switch destination {
        case .tray: return settings.trayEnabled && addToTray(supported) > 0
        case .airDrop: return settings.airDropEnabled && airDrop(supported.filter(\.isFileURL))
        }
    }

    public func showDropFailure(_ message: String) {
        tray.reportFailure(message)
        expand(.tray)
        pointerEnteredExpanded = true
    }

    @discardableResult
    func acceptTextDrop(_ text: String, action: TextDropAction,
                        pasteboard: NSPasteboard = .general,
                        openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }) -> Bool {
        guard let text = TextDropReader.clean(text) else { return false }
        switch action {
        case .translate:
            guard let url = TextDropReader.translationURL(text), openURL(url) else { return false }
            collapse()
        case .notes:
            guard settings.notesEnabled else { return false }
            notes.appendDroppedText(text)
            showTab(.notes)
        case .copy:
            pasteboard.clearContents()
            guard pasteboard.setString(text, forType: .string) else { return false }
            collapse()
        }
        return true
    }

    func captureWindow() {
        guard settings.trayEnabled, !isCapturingWindow else { return }
        guard DocumentWindowDrag.hasAccess else {
            showDropFailure("Allow Accessibility access, then try Capture Window again.")
            DocumentWindowDrag.requestAccess()
            return
        }
        let session = DocumentWindowDrag()
        guard session.captureFocusedWindow() else {
            showDropFailure("Switch to a document or browser window, then click Capture Window in Files.")
            return
        }
        isCapturingWindow = true
        tray.reportFailure("Reading the selected window…")
        Task { @MainActor [weak self] in
            let result = await session.resolve()
            guard let self else { return }
            self.isCapturingWindow = false
            guard self.settings.trayEnabled else { return }
            if let url = result.url { _ = self.addToTray([url]) }
            else { self.showDropFailure(result.message ?? "This window does not expose a saved document.") }
        }
    }

    /// Keeps dropped files in the tray and shows them.
    @discardableResult
    public func addToTray(_ urls: [URL]) -> Int {
        isFileDragNear = false
        setTargeted(nil, false)
        let added = tray.add(urls)
        expand(.tray)
        pointerEnteredExpanded = true
        if added > 0 {
            Haptics.perform(enabled: settings.hapticsEnabled)
        } else {
            NSSound.beep()
        }
        return added
    }

    public func showTab(_ tab: HomeTab) {
        if tab == .home || tab == .calendar { calendar.refreshAccess() }
        if tab == .reminders { reminders.refreshAccess() }
        if tab == .tray { tray.pruneMissing() }
        if tab == .mirror { camera.refresh() }
        // Editing belongs to the grid; going anywhere else ends it, and so does reopening the grid.
        isEditingShortcuts = false
        isEditingHome = false
        expand(ExpandTarget(tab))
    }

    /// Sends dropped files with AirDrop. Returns false if AirDrop can't take them.
    @discardableResult
    public func airDrop(_ urls: [URL]) -> Bool {
        isFileDragNear = false
        setTargeted(nil, false)
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            log.notice("AirDrop is not available for the dropped items")
            NSSound.beep()
            return false
        }
        Haptics.perform(enabled: settings.hapticsEnabled)
        NSApp.activate()
        service.perform(withItems: urls)
        return true
    }

    // MARK: Observation

    /// Clears choices that point at activities which have ended, so they don't come back
    /// expanded the next time the activity starts.
    private func observeActivities() {
        withObservationTracking {
            _ = activeActivities
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reconcile()
                self.observeActivities()
            }
        }
    }

    /// AI usage is checked only while it's on in Settings and its tile is switched on.
    private func syncAIUsageRefreshes() {
        if settings.aiUsageLive { aiUsage.startAutomaticRefreshes() } else { aiUsage.stopAutomaticRefreshes() }
    }

    /// Stats reads the system only while it's showing; music, a timer or another open view
    /// pushes it aside, and then there's nothing to update. Disk and network are read only while the panel (or the
    /// elongated Home's Stats widget, or Home's large Stats tile) is open, since the notch shows just memory and CPU.
    /// Home's Stats tile reads while Home is open even when the readout beside the camera is off.
    private func syncStatsSampling() {
        let panelSelected = expandTarget == .nook(.stats)
        let homeOpen = expandTarget == .home
        let elongatedHome = homeOpen && settings.appearance.nookLayout == .elongated
        let gridStats = homeOpen && !elongatedHome ? homeTiles.first { $0.item == .stats }?.size : nil
        let gridShowsReadings = gridStats.map { $0 != .small } ?? false
        guard settings.statsEnabled || panelSelected || gridShowsReadings else {
            stats.pause()
            stats.detailed = false
            return
        }
        let showsIdleStats = activeActivities.contains(.stats)
        let showsElongatedStats = elongatedHome && elongatedHomeTiles.contains { $0.item == .stats }
        let detailed = panelSelected || showsElongatedStats || gridStats == .large
        stats.detailed = detailed
        // Behind an open view the readout isn't showing, so there's nothing to update. Home
        // shows it in its Stats tile, or beside the grid.
        if detailed || gridShowsReadings || (showsIdleStats && (expandTarget == nil || (homeOpen && !elongatedHome))) {
            stats.start()
        } else {
            stats.pause()
        }
    }

    private func reconcile() {
        syncStatsSampling()
        let active = activeActivities
        if case .activity(let kind) = expandTarget, !active.contains(kind) {
            expandTarget = nil
            pumpAlerts()
        }
        if let preferredPrimary, !active.contains(preferredPrimary) {
            self.preferredPrimary = nil
        }
    }

    /// Looks up lyrics whenever the song changes (or lyrics are switched on or off).
    private func observeLyrics() {
        let info = nowPlaying.info
        lyrics.update(for: info, enabled: settings.nowPlayingEnabled && settings.lyricsEnabled)
        withObservationTracking {
            _ = nowPlaying.info?.title
            _ = nowPlaying.info?.artist
            _ = nowPlaying.info?.album
            _ = nowPlaying.info?.duration
            _ = settings.nowPlayingEnabled
            _ = settings.lyricsEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeLyrics() }
        }
    }

    /// Keeps each hook pointing at this copy of the app (for example after it moved), with the
    /// finished hook only while "Done" alerts are on.
    private func refreshAgentHooks() {
        for kind in settings.agentApprovals {
            guard let command = AgentHookSettings.currentCommand(socket: agents.socketPath, kind: kind),
                  !AgentHookSettings.isCurrent(kind, command: command, finished: settings.agentFinishedAlerts) else { continue }
            try? AgentHookSettings.install(kind, command: command, finished: settings.agentFinishedAlerts)
        }
    }

    private func observeMusicBars() {
        syncMusicBars()
        withObservationTracking {
            _ = nowPlaying.info?.isPlaying
            _ = settings.nowPlayingEnabled
            _ = settings.liveMusicBars
            _ = audioOutput.currentDevice?.id
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeMusicBars() }
        }
    }

    /// Listens to the Mac's sound only while Live music bars is on and something is playing.
    private func syncMusicBars() {
        let listens = settings.nowPlayingEnabled && settings.liveMusicBars && nowPlaying.info?.isPlaying == true
        if listens, audioTap.isRunning, audioTap.outputDevice != AudioHW.defaultOutputDevice() {
            // Switched to AirPods or speakers: listen through the new output.
            audioTap.stop()
        }
        if listens, !audioTap.isRunning {
            if !audioTap.start() { spectrum.reset() }
        } else if !listens, audioTap.isRunning {
            audioTap.stop()
            spectrum.reset()
        }
    }

    private func observeSettings() {
        withObservationTracking {
            _ = settings.pausedMediaLinger
            _ = settings.nowPlayingAppMode
            _ = settings.nowPlayingApps
            _ = settings.nowPlayingAppPatterns
            _ = settings.airDropEnabled
            _ = settings.trayEnabled
            _ = settings.mirrorEnabled
            _ = settings.clipboardEnabled
            _ = settings.clipboardReadsImages
            _ = settings.clipboardExcludedApps
            _ = settings.clipboardKeepsImages
            _ = settings.notesEnabled
            _ = settings.downloadsEnabled
            _ = settings.agentApprovals
            _ = settings.headphoneAlertsEnabled
            _ = settings.agentFinishedAlerts
            _ = settings.agentWatchesTranscript
            _ = settings.remindersEnabled
            _ = settings.statsEnabled
            _ = settings.keyboardShortcutsEnabled
            _ = settings.checksForUpdates
            _ = settings.installsUpdatesAutomatically
            _ = settings.sharesUsage
            _ = settings.aiUsageEnabled
            _ = settings.aiUsageInNotch
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.settings.headphoneAlertsEnabled { self.audioRoute.start() } else { self.audioRoute.stop() }
                self.nowPlaying.lingerDuration = self.settings.pausedMediaLinger
                self.nowPlaying.appFilter = self.settings.mediaAppFilter
                if !self.acceptsFileDrops && !self.isTextDrag {
                    self.isFileDragNear = false
                    self.setTargeted(nil, false)
                }
                if case .tray = self.expandTarget, !self.settings.trayEnabled { self.collapse() }
                if case .mirror = self.expandTarget, !self.settings.mirrorEnabled { self.collapse() }
                if case .clipboard = self.expandTarget, !self.settings.clipboardEnabled { self.collapse() }
                if case .notes = self.expandTarget, !self.settings.notesEnabled { self.collapse() }
                if self.settings.remindersEnabled { self.reminders.start() } else { self.reminders.stop() }
                self.syncStatsSampling()
                if !self.settings.statsEnabled, case .nook(.stats) = self.expandTarget { self.collapse() }
                if self.settings.keyboardShortcutsEnabled { self.hotKeys.register() } else { self.hotKeys.unregister() }
                self.updater.installsAutomatically = self.settings.checksForUpdates && self.settings.installsUpdatesAutomatically
                if self.settings.checksForUpdates { self.updater.startAutomaticChecks() } else { self.updater.stopAutomaticChecks() }
                if self.settings.sharesUsage { self.usage.start(isNewInstall: false) } else { self.usage.stop() }
                self.agents.enabledKinds = self.settings.agentApprovals
                self.agents.watchesTranscripts = self.settings.agentWatchesTranscript
                if self.settings.agentApprovalsEnabled {
                    self.agents.start()
                    self.refreshAgentHooks()
                } else {
                    self.agents.stop()
                }
                if self.settings.downloadsEnabled {
                    self.downloads.start()
                    self.downloadProgress.start()
                } else {
                    self.downloads.stop()
                    self.downloadProgress.stop()
                }
                self.clipboard.readsTextInImages = self.settings.clipboardReadsImages
                self.clipboard.excludedApps = self.settings.clipboardExcludedApps
                self.clipboard.keepsImages = self.settings.clipboardKeepsImages
                if self.settings.clipboardEnabled {
                    self.clipboard.start()
                } else {
                    self.clipboard.stop()
                }
                self.syncAIUsageRefreshes()
                if !self.settings.aiUsageLive, case .nook(.aiUsage) = self.expandTarget { self.collapse() }
                self.observeSettings()
            }
        }
    }
}
