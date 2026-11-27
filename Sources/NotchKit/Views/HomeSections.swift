import SwiftUI

// Home in the standard layout: up to three sections side by side, split by hairlines.
// - Live: a call or the mic, music, Stats and AI usage, two at most. One fills the section as
//   a card; two share it, one above the other. Clicking a card (not its buttons) opens that activity's full view.
// - Calendar: the next event.
// - Timer: presets, or, while a timer or the stopwatch runs, that clock above the presets.
// - Shortcuts: shares the Timer section when there isn't a section left for it.

enum HomeSection: Hashable, Identifiable {
    case live([LiveItem])
    case calendar
    /// The clocks running now (timer, stopwatch), shown above the presets.
    case timer(running: [LiveItem])
    case shortcuts
    /// No room for both on their own, so they share the last section.
    case timerAndShortcuts
    case aiUsage

    enum LiveItem: Hashable {
        case call, music, timer, stopwatch, stats, aiUsage

        var activity: ActivityKind {
            switch self {
            case .call: .call
            case .music: .nowPlaying
            case .timer: .timer
            case .stopwatch: .stopwatch
            case .stats: .stats
            case .aiUsage: .aiUsage
            }
        }
    }

    /// Cards that share the live section, like two apps playing.
    static let maximumLive = 2

    static let maximum = 3

    /// Stable across changes to what's running, so a section animates instead of being replaced.
    var id: String {
        switch self {
        case .live: "live"
        case .calendar: "calendar"
        case .timer, .timerAndShortcuts: "timer"
        case .shortcuts: "shortcuts"
        case .aiUsage: "aiUsage"
        }
    }

    @MainActor static func sections(for model: IslandModel) -> [HomeSection] {
        let active = model.activeActivities
        var live: [LiveItem] = []
        if active.contains(.call) { live.append(.call) }
        // Paused music can linger in Home; anything live comes before it.
        let musicIsLive = active.contains(.nowPlaying)
        if model.homeHasMedia, musicIsLive { live.append(.music) }
        if active.contains(.stats) { live.append(.stats) }
        if active.contains(.aiUsage) { live.append(.aiUsage) }
        if model.homeHasMedia, !musicIsLive { live.append(.music) }
        live = Array(live.prefix(maximumLive))
        var clocks: [LiveItem] = []
        if active.contains(.timer) { clocks.append(.timer) }
        if active.contains(.stopwatch) { clocks.append(.stopwatch) }

        var sections: [HomeSection] = live.isEmpty ? [] : [.live(live)]
        if model.showsCalendarRow { sections.append(.calendar) }
        let timer = model.settings.timerEnabled || !clocks.isEmpty
        let shortcuts = !model.favoriteShortcuts.isEmpty
        // A running clock already halves the Timer section, so Shortcuts can't share it too.
        if timer, shortcuts, clocks.isEmpty, sections.count + 2 > maximum {
            sections.append(.timerAndShortcuts)
        } else {
            if timer { sections.append(.timer(running: clocks)) }
            if shortcuts { sections.append(.shortcuts) }
        }
        if model.settings.aiUsageLive, model.settings.aiUsageShowHomeWidget, !live.contains(.aiUsage), !model.aiUsage.visibleUsages(selected: model.settings.selectedAIProviders).isEmpty, sections.count < maximum {
            sections.append(.aiUsage)
        }
        return Array(sections.prefix(maximum))
    }

    @MainActor static func dashboardDefaults(for model: IslandModel) -> HomeDashboardLayout {
        let widgets: [HomeDashboardWidget] = sections(for: model).flatMap { section in
            switch section {
            case .live(let items):
                return items.compactMap { item -> HomeDashboardWidget? in
                    switch item {
                    case .music, .call: .music
                    case .stats: .stats
                    case .aiUsage: .aiUsage
                    case .timer, .stopwatch: nil
                    }
                }
            case .calendar: return [.calendar]
            case .timer: return [.timer]
            case .shortcuts: return [.shortcuts]
            case .timerAndShortcuts: return [.timer, .shortcuts]
            case .aiUsage: return [.aiUsage]
            }
        }
        var seen = Set<HomeDashboardWidget>()
        return HomeDashboardLayout(widgets: Array(widgets.filter { seen.insert($0).inserted }.prefix(3)))
    }
}

struct StandardHomeBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        if let draft = model.homeDashboardDraft {
            HomeDashboardEditor(model: model, layout: draft) { dashboardCard($0, editing: true) }
        } else if let dashboard = model.settings.homeDashboard {
            customDashboard(dashboard)
        } else {
            automaticLayout
        }
    }

    private var automaticLayout: some View {
        let sections = HomeSection.sections(for: model)
        return HStack(alignment: .top, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                if index > 0, case .live = sections[index - 1] {
                    Color.clear.frame(width: 14 * s)
                } else if index > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1)
                        .padding(.vertical, 8 * s)
                        .padding(.horizontal, 12 * s)
                }
                view(for: section)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.bottom, 2 * s)
        .overlay {
            if sections.isEmpty {
                Text("Nothing live right now")
                    .font(.system(size: 13 * s, weight: .medium))
                    .foregroundStyle(NotchColor.secondaryText)
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.15), value: sections)
    }

    private func customDashboard(_ layout: HomeDashboardLayout) -> some View {
        GeometryReader { geometry in
            let frames = layout.frames(in: geometry.size.width, rowHeight: IslandMetrics.Nook.body * s,
                                       gap: IslandMetrics.Nook.dashboardGap * s, presentation: .home)
            ZStack(alignment: .topLeading) {
                ForEach(layout.widgets) { widget in
                    if let frame = frames[widget] {
                        dashboardCard(widget)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if layout.widgets.isEmpty {
                Text("Add cards from Edit Home")
                    .font(.system(size: 13 * s, weight: .medium))
                    .foregroundStyle(NotchColor.secondaryText)
            }
        }
    }

    private func dashboardCard(_ widget: HomeDashboardWidget, editing: Bool = false) -> some View {
        GeometryReader { geometry in
            dashboardContent(widget, editing: editing, wide: geometry.size.width >= 250 * s,
                             tall: geometry.size.height >= 225 * s)
                .sectionFrame()
        }
    }

    @ViewBuilder
    private func dashboardContent(_ widget: HomeDashboardWidget, editing: Bool, wide: Bool, tall: Bool) -> some View {
        switch widget {
        case .music where model.calls.session != nil && model.settings.callsEnabled:
            LiveCard(model: model, item: .call, compact: false, showsOpenIndicator: !editing, roomyMedia: tall)
        case .music where model.homeHasMedia:
            LiveCard(model: model, item: .music, compact: false, showsOpenIndicator: !editing, roomyMedia: tall)
        case .music:
            dashboardMessage(widget, "Nothing playing")
        case .calendar where model.showsCalendarRow:
            dashboardSurface {
                CalendarSection(model: model, calendar: model.calendar, eventColumns: wide ? 2 : 1,
                                eventRows: tall ? 3 : 1)
            }
        case .timer where model.settings.timerEnabled:
            let active = model.activeActivities
            let clocks: [HomeSection.LiveItem] = [.timer, .stopwatch].filter { active.contains($0.activity) }
            dashboardSurface {
                timerSection(running: clocks, extraPreset: wide || tall, tall: tall, dashboard: true, editing: editing)
            }
        case .shortcuts where !model.favoriteShortcuts.isEmpty:
            dashboardSurface {
                ShortcutsSection(model: model, compact: false, dashboardColumns: wide ? 2 : 1,
                                 dashboardRows: tall ? 4 : 2)
            }
        case .stats:
            LiveCard(model: model, item: .stats, compact: false, detailed: true, showsOpenIndicator: !editing)
        case .bluetooth:
            dashboardSurface {
                VStack(alignment: .leading, spacing: 4 * s) {
                    Button { model.showTab(.bluetooth) } label: {
                        SectionHeader(symbol: widget.symbol, tint: NotchColor.blue, title: widget.title, showsChevron: true)
                    }
                    .buttonStyle(PressableButtonStyle())
                    BluetoothPanelBody(compact: !wide)
                }
            }
        case .aiUsage where model.settings.aiUsageLive:
            dashboardSurface {
                AIUsageHomeWidget(aiUsage: model.aiUsage, settings: model.settings, onOpen: { model.showTab(.aiUsage) })
                    .dashboardDetails(columns: wide ? 2 : 1, rows: tall ? 4 : (wide ? 1 : 0))
            }
        case .shortcuts:
            dashboardMessage(widget, "No favourite shortcuts")
        case .calendar, .timer, .aiUsage:
            dashboardMessage(widget, "Turn on in Settings")
        }
    }

    private func dashboardMessage(_ widget: HomeDashboardWidget, _ message: LocalizedStringKey) -> some View {
        dashboardSurface {
            VStack(alignment: .leading, spacing: 8 * s) {
                SectionHeader(symbol: widget.symbol, tint: NotchColor.blue, title: widget.title)
                Text(message)
                    .font(.system(size: 11 * s))
                    .foregroundStyle(NotchColor.secondaryText)
            }
        }
    }

    private func dashboardSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(9 * s)
            .sectionFrame()
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16 * s))
    }

    @ViewBuilder
    private func view(for section: HomeSection) -> some View {
        switch section {
        case .live(let items):
            VStack(spacing: 6 * s) {
                ForEach(items, id: \.self) { item in
                    LiveCard(model: model, item: item, compact: items.count > 1)
                        .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
            }
            .frame(width: 196 * s)
            .frame(maxHeight: .infinity)
            .transition(.scale(scale: 0.92, anchor: .leading).combined(with: .opacity))
        case .calendar:
            CalendarSection(model: model, calendar: model.calendar)
                .sectionFrame()
        case .timer(let running):
            timerSection(running: running)
        case .shortcuts:
            ShortcutsSection(model: model, compact: false)
                .sectionFrame()
        case .timerAndShortcuts:
            VStack(alignment: .leading, spacing: 12 * s) {
                TimerSection(model: model, compact: true)
                ShortcutsSection(model: model, compact: true)
            }
            .sectionFrame()
        case .aiUsage:
            AIUsageHomeWidget(aiUsage: model.aiUsage, settings: model.settings, onOpen: { model.showTab(.aiUsage) })
                .sectionFrame()
        }
    }

    private func timerSection(running: [HomeSection.LiveItem], extraPreset: Bool = false,
                              tall: Bool = false, dashboard: Bool = false, editing: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            ForEach(running, id: \.self) { item in
                LiveCard(model: model, item: item, compact: true, showsOpenIndicator: !editing)
                    .frame(height: (dashboard ? (tall ? 54 : 42) : 50) * s)
                    .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
            }
            if running.count < 2 || tall {
                TimerSection(model: model, compact: !running.isEmpty && !tall, showsHeader: running.isEmpty,
                             extraPreset: extraPreset)
            }
        }
        .sectionFrame()
    }
}

private extension View {
    func sectionFrame() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A section's name, with a chevron when clicking it opens more.
private struct SectionHeader: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    var showsChevron = false
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 6 * s) {
            Image(systemName: symbol)
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 9 * s, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }
        .frame(height: 16 * s)
    }
}

// MARK: Live

/// A live activity as a card. Clicking anywhere but its buttons opens that activity's full view.
/// Compact is one row, for when it shares its section.
private struct LiveCard: View {
    let model: IslandModel
    let item: HomeSection.LiveItem
    let compact: Bool
    /// A card the user sized themselves: it says more when it has the room.
    var detailed = false
    var showsOpenIndicator = true
    var roomyMedia = false
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: (compact ? 12 : 16) * s, style: .continuous)
        Group {
            switch item {
            case .call: LiveCall(model: model, compact: compact, roomy: roomyMedia)
            case .music: LiveMusic(service: model.nowPlaying, lyrics: model.showsLyrics ? model.lyrics.current : nil,
                                   compact: compact, roomy: roomyMedia)
            case .timer: LiveTimer(model: model)
            case .stopwatch: LiveStopwatch(model: model)
            case .stats: LiveStats(stats: model.stats, compact: compact, detailed: detailed)
            case .aiUsage: LiveAIUsage(model: model, compact: compact)
            }
        }
        .padding(.horizontal, (compact ? 8 : 10) * s)
        .padding(.vertical, (compact ? 6 : 10) * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .leading : .topLeading)
        .background(shape.fill(Color.white.opacity(isHovering && opensFullView ? 0.11 : 0.07)))
        .overlay(alignment: .topTrailing) {
            if opensFullView && !compact && showsOpenIndicator {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 9 * s, weight: .bold))
                    .foregroundStyle(Color.white.opacity(isHovering ? 0.7 : 0.3))
                    .padding(10 * s)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(shape)
        .onTapGesture {
            guard opensFullView else { return }
            model.expand(.activity(item.activity))
        }
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help(opensFullView ? "Open" : "")
        .accessibilityAddTraits(opensFullView ? .isButton : [])
    }

    /// Paused music can stay on Home after its own view has gone.
    private var opensFullView: Bool {
        item == .stats || model.activeActivities.contains(item.activity)
    }
}

/// Memory and CPU, as in the notch. Dashboard cards also use available space for disk and network.
private struct LiveStats: View {
    let stats: StatsService
    let compact: Bool
    var detailed = false
    @Environment(\.notchScale) private var s

    var body: some View {
        let snapshot = stats.snapshot
        let memory = snapshot.memoryTotal > 0 ? snapshot.memory : nil
        let cpu = stats.hasReading ? snapshot.cpu : nil
        let values = HStack(spacing: (compact ? 10 : 16) * s) {
            LiveReading(caption: "MEM", share: memory, level: snapshot.memoryPressure, size: compact ? 15 : 22)
            LiveReading(caption: "CPU", share: cpu, level: nil, size: compact ? 15 : 22)
        }
        if compact {
            HStack(spacing: 8 * s) {
                LiveCardTitle(symbol: "gauge.with.dots.needle.33percent", tint: NotchColor.green, title: "Stats")
                Spacer(minLength: 4 * s)
                values
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                LiveCardTitle(symbol: "gauge.with.dots.needle.33percent", tint: NotchColor.green, title: "Stats")
                if detailed {
                    ViewThatFits {
                        detailRow(readings)
                        VStack(spacing: 10 * s) {
                            detailRow(readings.prefix(2))
                            detailRow(readings.suffix(2))
                        }
                        detailRow(readings.prefix(3))
                        detailRow(readings.prefix(2))
                        values
                    }
                    .padding(.top, 10 * s)
                    .frame(maxHeight: .infinity, alignment: .center)
                } else {
                    Spacer(minLength: 6 * s)
                    values
                }
            }
        }
    }

    private var readings: [LiveDetailedReading] {
        let snapshot = stats.snapshot
        let hasMemory = snapshot.memoryTotal > 0, hasDisk = snapshot.diskTotal > 0, ready = stats.hasReading
        return [
            LiveDetailedReading(
                caption: "MEM", value: hasMemory ? StatsMath.percent(snapshot.memory) : "–",
                tint: hasMemory ? snapshot.memoryPressure.tint : NotchColor.secondaryText,
                detail: hasMemory ? "\(StatsMath.bytes(Int64(snapshot.memoryUsed))) of \(StatsMath.bytes(Int64(snapshot.memoryTotal)))" : ""),
            LiveDetailedReading(
                caption: "CPU", value: ready ? StatsMath.percent(snapshot.cpu) : "–",
                tint: ready ? StatsMath.level(snapshot.cpu).tint : NotchColor.secondaryText,
                detail: "\(ProcessInfo.processInfo.activeProcessorCount) cores"),
            LiveDetailedReading(
                caption: "DISK", value: hasDisk ? StatsMath.bytes(snapshot.diskFree) : "–",
                tint: hasDisk ? .white : NotchColor.secondaryText,
                detail: hasDisk ? "free of \(StatsMath.bytes(snapshot.diskTotal))" : ""),
            LiveDetailedReading(
                caption: "NET ↓", value: ready ? StatsMath.rate(snapshot.networkIn) : "–",
                tint: ready ? .white : NotchColor.secondaryText,
                detail: ready ? "↑ \(StatsMath.rate(snapshot.networkOut))" : ""),
        ]
    }

    private func detailRow(_ readings: some RandomAccessCollection<LiveDetailedReading>) -> some View {
        HStack(alignment: .top, spacing: 10 * s) {
            ForEach(Array(readings), id: \.caption) { $0 }
        }
    }
}

/// One reading with a stable ideal width so changing values don't switch the card's layout.
private struct LiveDetailedReading: View {
    let caption: String
    let value: String
    let tint: Color
    let detail: String
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption)
                .font(.system(size: 8 * s, weight: .bold))
                .kerning(0.3)
                .foregroundStyle(NotchColor.secondaryText)
            Text(value)
                .font(.system(size: 22 * s, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.system(size: 9.5 * s, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(NotchColor.secondaryText)
                .minimumScaleFactor(0.7)
        }
        .lineLimit(1)
        .frame(minWidth: 72 * s, idealWidth: 72 * s, maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The lowest AI agent limit left and when the first one resets. Compact is one row.
private struct LiveAIUsage: View {
    let model: IslandModel
    let compact: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        let windows = model.aiUsage.visibleUsages(selected: model.settings.selectedAIProviders).flatMap(\.windows)
        let remaining = windows.compactMap(\.remainingPercent).min()
        let tint = remaining.map { $0 > 25 ? NotchColor.green : NotchColor.yellow } ?? NotchColor.secondaryText
        let value = Text(remaining.map { "\(Int($0.rounded()))%" } ?? "–")
            .font(.system(size: (compact ? 15 : 22) * s, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(tint)
        if compact {
            HStack(spacing: 8 * s) {
                LiveCardTitle(symbol: "sparkles", tint: NotchColor.orange, title: "AI usage")
                Spacer(minLength: 4 * s)
                HStack(alignment: .firstTextBaseline, spacing: 3 * s) {
                    value
                    Text("left").font(.system(size: 10 * s, weight: .medium)).foregroundStyle(NotchColor.secondaryText)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                LiveCardTitle(symbol: "sparkles", tint: NotchColor.orange, title: "AI Agent Usage")
                Spacer(minLength: 6 * s)
                HStack(alignment: .firstTextBaseline, spacing: 4 * s) {
                    value
                    Text("left").font(.system(size: 11 * s, weight: .medium)).foregroundStyle(NotchColor.secondaryText)
                }
                if let reset = windows.compactMap(\.resetsAt).filter({ $0 > Date() }).min() {
                    Text("Resets \(reset, style: .relative)")
                        .font(.system(size: 10 * s, weight: .medium))
                        .foregroundStyle(NotchColor.secondaryText)
                        .lineLimit(1)
                }
            }
        }
    }
}

/// A live card's symbol and name.
private struct LiveCardTitle: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 6 * s) {
            Image(systemName: symbol)
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}

/// A caption over a percentage, coloured by how busy it is.
private struct LiveReading: View {
    let caption: LocalizedStringKey
    let share: Double?
    /// Colour override (memory follows pressure, not percentage).
    let level: StatsMath.Level?
    let size: CGFloat
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(caption)
                .font(.system(size: 8 * s, weight: .bold))
                .kerning(0.3)
                .foregroundStyle(NotchColor.secondaryText)
            Text(share.map(StatsMath.percent) ?? "–")
                .font(.system(size: size * s, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(share.map { (level ?? StatsMath.level($0)).tint } ?? NotchColor.secondaryText)
        }
        .lineLimit(1)
    }
}

/// App, what it's doing and for how long, then mute and hang up (or show the app). Compact puts
/// the buttons beside the name.
private struct LiveCall: View {
    let model: IslandModel
    let compact: Bool
    var roomy = false
    @Environment(\.notchScale) private var s

    var body: some View {
        if let session = model.calls.session {
            let tint = session.isCall ? NotchColor.green : NotchColor.orange
            let title = HStack(spacing: 8 * s) {
                AppIconView(icon: model.calls.appIcon, symbol: session.isCall ? "phone.fill" : "mic.fill", tint: tint,
                            size: (roomy ? 44 : (compact ? 24 : 30)) * s)
                VStack(alignment: .leading, spacing: 1 * s) {
                    Text(session.appName)
                        .font(.system(size: (compact ? 12 : 13) * s, weight: .semibold))
                        .foregroundStyle(.white)
                    if let message = model.calls.hangUpMessage {
                        Text(message)
                            .font(.system(size: 10 * s, weight: .medium))
                            .foregroundStyle(NotchColor.secondaryText)
                    } else {
                        HStack(spacing: 4 * s) {
                            Text(session.isCall ? "On Call" : "Mic")
                            Text(session.startDate, style: .timer)
                                .monospacedDigit()
                        }
                        .font(.system(size: (compact ? 10.5 : 11) * s, weight: .medium))
                        .foregroundStyle(tint)
                    }
                }
                .lineLimit(roomy ? 2 : 1)
            }
            if compact {
                HStack(spacing: 6 * s) {
                    title
                    Spacer(minLength: 4 * s)
                    buttons(session, size: 28 * s)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    title
                        .padding(.trailing, 12 * s)
                    Spacer(minLength: 6 * s)
                    HStack(spacing: 8 * s) {
                        if session.usesCamera {
                            Image(systemName: "video.fill")
                                .font(.system(size: 11 * s, weight: .semibold))
                                .foregroundStyle(NotchColor.green)
                                .accessibilityLabel(Text("Camera in use"))
                        }
                        Spacer(minLength: 0)
                        buttons(session, size: (roomy ? 40 : 34) * s)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func buttons(_ session: CallMonitor.Session, size: CGFloat) -> some View {
        let tint = session.isCall ? NotchColor.green : NotchColor.orange
        if model.microphone.canMute {
            let muted = model.microphone.isMuted
            CircleButton(
                symbol: muted ? "mic.slash.fill" : "mic.fill",
                size: size,
                foreground: muted ? .white : NotchColor.orange,
                background: muted ? NotchColor.red : NotchColor.orange.opacity(0.22),
                label: muted ? "Unmute Microphone" : "Mute Microphone"
            ) { model.microphone.toggle() }
        }
        if model.calls.canHangUp {
            CircleButton(symbol: "phone.down.fill", size: size, foreground: .white, background: NotchColor.red, label: "Hang Up") {
                Task { @MainActor in
                    if await model.calls.hangUp() == .sent { model.collapse() }
                }
            }
            .help(CallHangup.shortcut(for: session.bundleIdentifier)?.asksToConfirm == true
                  ? "Leave the call (\(session.appName) asks you to confirm)"
                  : "Hang up")
        } else if !compact || !model.microphone.canMute {
            CircleButton(symbol: "arrow.up.forward", size: size, foreground: .white, background: tint, label: "Show \(session.appName)") {
                model.calls.showApp()
                model.collapse()
            }
        }
    }
}

private struct LiveTimer: View {
    let model: IslandModel

    var body: some View {
        if let timer = model.timer.timer {
            LiveClock(
                symbol: timer.mode.symbol,
                title: timer.mode.title,
                isPaused: timer.isPaused,
                pauseLabel: timer.isPaused ? "Resume Timer" : "Pause Timer",
                cancelLabel: "Cancel Timer",
                togglePause: { model.timer.togglePause() },
                cancel: { model.cancelTimer() }
            ) {
                CountdownText(timer: timer)
            }
        }
    }
}

private struct LiveStopwatch: View {
    let model: IslandModel

    var body: some View {
        let isRunning = model.stopwatch.stopwatch?.isRunning == true
        LiveClock(
            symbol: "stopwatch",
            title: "Stopwatch",
            isPaused: !isRunning,
            pauseLabel: isRunning ? "Pause Stopwatch" : "Resume Stopwatch",
            cancelLabel: "Reset Stopwatch",
            togglePause: { model.stopwatch.togglePause() },
            cancel: { model.resetStopwatch() }
        ) {
            TimelineView(.animation(minimumInterval: 0.1, paused: !isRunning)) { context in
                Text(StopwatchFormat.text(model.stopwatch.elapsed(at: context.date)))
            }
        }
    }
}

/// A running clock in one row: its name and time, then cancel and pause.
private struct LiveClock<Clock: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let isPaused: Bool
    let pauseLabel: LocalizedStringKey
    let cancelLabel: LocalizedStringKey
    let togglePause: () -> Void
    let cancel: () -> Void
    @ViewBuilder var clock: Clock
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 6 * s) {
            VStack(alignment: .leading, spacing: 0) {
                // Beside a live card the section is narrow; the symbol alone is enough.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4 * s) {
                        Image(systemName: symbol)
                        Text(title)
                    }
                    Image(systemName: symbol)
                }
                .font(.system(size: 10 * s, weight: .semibold))
                .foregroundStyle(NotchColor.secondaryText)
                .lineLimit(1)
                clock
                    .font(.system(size: 18 * s, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(NotchColor.orange.opacity(isPaused ? 0.6 : 1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 2 * s)
            CircleButton(symbol: "xmark", size: 26 * s, foreground: .white, background: NotchColor.buttonFill, label: cancelLabel, action: cancel)
            CircleButton(
                symbol: isPaused ? "play.fill" : "pause.fill",
                size: 26 * s,
                foreground: NotchColor.orange,
                background: NotchColor.orange.opacity(0.22),
                label: pauseLabel,
                action: togglePause
            )
        }
    }
}

/// Artwork, title and the transport controls. Compact keeps play and next beside the title.
private struct LiveMusic: View {
    let service: NowPlayingService
    /// Shown as one line under the title when the song has timed lyrics.
    let lyrics: SyncedLyrics?
    let compact: Bool
    var roomy = false
    @Environment(\.notchScale) private var s

    var body: some View {
        let info = service.info
        let playPause = GlyphButton(symbol: info?.isPlaying == true ? "pause.fill" : "play.fill", size: (compact ? 14 : 17) * s, label: info?.isPlaying == true ? "Pause" : "Play") {
            service.togglePlayPause()
        }
        let next = GlyphButton(symbol: "forward.fill", size: 12 * s, label: "Next Track") { service.nextTrack() }
        let title = HStack(spacing: 8 * s) {
            Button { service.openSourceApp() } label: {
                ArtworkView(artwork: service.artwork, fallbackIcon: service.appIcon,
                            size: (roomy ? 66 : (compact ? 26 : 40)) * s, cornerRadius: (compact ? 6 : 9) * s)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("Open player"))
            VStack(alignment: .leading, spacing: (compact ? 0 : 2) * s) {
                Text(info?.title ?? "")
                    .font(.system(size: (compact ? 12 : 12.5) * s, weight: .semibold))
                    .foregroundStyle(.white)
                Text(info?.artist.isEmpty == false ? info?.artist ?? "" : service.appName ?? "")
                    .font(.system(size: 10.5 * s))
                    .foregroundStyle(NotchColor.secondaryText)
            }
            .lineLimit(roomy ? 2 : 1)
        }
        if compact {
            HStack(spacing: 2 * s) {
                title
                Spacer(minLength: 2 * s)
                playPause
                next
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                title
                    .padding(.trailing, 12 * s)
                if let lyrics {
                    LyricsLine(lyrics: lyrics, service: service, size: 11 * s, alignment: .leading)
                        .frame(height: 16 * s)
                        .padding(.top, 4 * s)
                }
                Spacer(minLength: 4 * s)
                MiniProgress(service: service)
                    .frame(height: 3 * s)
                if roomy, let info, let duration = info.duration {
                    TimelineView(.animation(minimumInterval: 1, paused: !info.isPlaying)) { context in
                        HStack {
                            Text(TimeFormatting.clock(info.elapsed(at: context.date) ?? 0))
                            Spacer()
                            Text(TimeFormatting.clock(duration))
                        }
                        .font(.system(size: 10 * s, weight: .medium).monospacedDigit())
                        .foregroundStyle(NotchColor.secondaryText)
                        .padding(.top, 4 * s)
                    }
                }
                HStack(spacing: 16 * s) {
                    GlyphButton(symbol: "backward.fill", size: 12 * s, label: "Previous Track") { service.previousTrack() }
                    playPause
                    next
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4 * s)
            }
        }
    }
}

// MARK: Calendar

/// The next event, or a way to connect the calendar. Opens the month once connected.
private struct CalendarSection: View {
    let model: IslandModel
    let calendar: CalendarService
    var eventColumns = 1
    var eventRows = 1
    @Environment(\.notchScale) private var s

    var body: some View {
        switch calendar.access {
        case .notAsked:
            VStack(alignment: .leading, spacing: 6 * s) {
                SectionHeader(symbol: "calendar", tint: NotchColor.red, title: "Calendar")
                message("See your next event here.")
                Button("Connect") { calendar.requestAccess() }
                    .buttonStyle(QuickActionStyle(tint: NotchColor.red, scale: s))
            }
        case .denied, .limited:
            VStack(alignment: .leading, spacing: 6 * s) {
                SectionHeader(symbol: "calendar", tint: NotchColor.red, title: "Calendar")
                message("Calendar access is off.")
                Button("Allow Access") { calendar.openPrivacySettings() }
                    .buttonStyle(QuickActionStyle(tint: NotchColor.red, scale: s))
                    .help("Turn on Dynamic Ledge in Privacy & Security › Calendars")
            }
        case .granted:
            Button { model.showTab(.calendar) } label: {
                VStack(alignment: .leading, spacing: 6 * s) {
                    SectionHeader(symbol: "calendar", tint: NotchColor.red, title: "Calendar", showsChevron: true)
                    TimelineView(.everyMinute) { context in
                        upcomingEvents(at: context.date)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    @ViewBuilder
    private func upcomingEvents(at date: Date) -> some View {
        let events = calendar.events.filter { !$0.isAllDay && $0.end > date }.sorted { $0.start < $1.start }
        if events.isEmpty {
            message("No more events this week")
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: eventColumns),
                      alignment: .leading, spacing: 8 * s) {
                ForEach(events.prefix(eventColumns * eventRows)) { event in
                    VStack(alignment: .leading, spacing: 4 * s) {
                        Text(event.title)
                            .font(.system(size: 13 * s, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(eventColumns == 1 ? 2 : 1)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(CalendarRules.relativeLabel(for: event, at: date))
                            .font(.system(size: 11 * s, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(event.isHappening(at: date) ? NotchColor.green : NotchColor.secondaryText)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 11 * s, weight: .medium))
            .foregroundStyle(NotchColor.secondaryText)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: Timer

/// "Timer ›" opens the full timer; the capsules start one straight away.
private struct TimerSection: View {
    let model: IslandModel
    let compact: Bool
    var showsHeader = true
    var extraPreset = false
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            if showsHeader {
                Button {
                    model.timerPanelMode = .timer
                    model.showTab(.timers)
                } label: {
                    SectionHeader(symbol: "timer", tint: NotchColor.orange, title: "Timer", showsChevron: true)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .help("Any length, Pomodoro or Stopwatch")
                .accessibilityLabel(Text("Timer"))
            }
            ViewThatFits(in: .horizontal) {
                presetRow(TimerService.presets.prefix(extraPreset ? 4 : 3))
                VStack(alignment: .leading, spacing: 6 * s) {
                    presetRow(TimerService.presets.prefix(2))
                    presetRow(TimerService.presets.prefix(extraPreset ? 4 : 3).dropFirst(2))
                }
            }
            if !compact {
                Button {
                    model.startSession(.focus)
                } label: {
                    Label("Focus \(model.settings.focusMinutes)m", systemImage: TimerMode.focus.symbol)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(QuickActionStyle(tint: NotchColor.orange, scale: s))
                .help("Focus for \(model.settings.focusMinutes) minutes, then take a \(model.settings.breakMinutes) minute break")
                .accessibilityLabel(Text("Start a \(model.settings.focusMinutes) minute focus session"))
            }
        }
    }

    private func presetRow(_ presets: ArraySlice<TimeInterval>) -> some View {
        HStack(spacing: 6 * s) {
            ForEach(presets, id: \.self) { preset in
                Button("\(Int(preset / 60))m") { model.startTimer(preset) }
                    .buttonStyle(QuickActionStyle(tint: NotchColor.orange, scale: s, width: 38 * s))
                    .accessibilityLabel(Text("Start \(TimeFormatting.spoken(preset)) timer"))
            }
        }
    }
}

// MARK: Shortcuts

/// The favourite shortcuts, one tap to run. Compact shows only the first.
private struct ShortcutsSection: View {
    let model: IslandModel
    let compact: Bool
    var dashboardColumns: Int?
    var dashboardRows = 2
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            SectionHeader(symbol: "bolt.fill", tint: NotchColor.blue, title: "Shortcuts")
            if let dashboardColumns {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: dashboardColumns),
                          alignment: .leading, spacing: 6 * s) {
                    ForEach(model.favoriteShortcuts.prefix(dashboardColumns * dashboardRows), id: \.self) { name in
                        shortcut(name, labelWidth: 88 * s)
                    }
                }
            } else {
                ForEach(model.favoriteShortcuts.prefix(compact ? 1 : 3), id: \.self) { name in
                    shortcut(name, labelWidth: 112 * s)
                }
            }
        }
    }

    private func shortcut(_ name: String, labelWidth: CGFloat) -> some View {
        let isRunning = model.shortcuts.running.contains(name)
        return Button {
            model.shortcuts.run(name)
        } label: {
            HStack(spacing: 5 * s) {
                if isRunning {
                    ProgressView().controlSize(.mini)
                }
                Text(name)
                    .truncationMode(.tail)
                    .frame(maxWidth: labelWidth, alignment: .leading)
            }
        }
        .buttonStyle(QuickActionStyle(tint: NotchColor.blue, scale: s))
        .disabled(isRunning)
        .help(name)
        .accessibilityLabel(Text("Run shortcut \(name)"))
    }
}
