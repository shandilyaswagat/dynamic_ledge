import SwiftUI

// Home in the standard layout: up to three sections side by side, split by hairlines.
// - Live: a call or the mic, and music. One fills the section as a card; two share it, one
//   above the other. Clicking a card (not its buttons) opens that activity's full view.
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

    enum LiveItem: Hashable {
        case call, music, timer, stopwatch

        var activity: ActivityKind {
            switch self {
            case .call: .call
            case .music: .nowPlaying
            case .timer: .timer
            case .stopwatch: .stopwatch
            }
        }
    }

    static let maximum = 3

    /// Stable across changes to what's running, so a section animates instead of being replaced.
    var id: String {
        switch self {
        case .live: "live"
        case .calendar: "calendar"
        case .timer, .timerAndShortcuts: "timer"
        case .shortcuts: "shortcuts"
        }
    }

    @MainActor static func sections(for model: IslandModel) -> [HomeSection] {
        let active = model.activeActivities
        var live: [LiveItem] = []
        if active.contains(.call) { live.append(.call) }
        if model.homeHasMedia { live.append(.music) }
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
        return Array(sections.prefix(maximum))
    }
}

struct StandardHomeBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        let sections = HomeSection.sections(for: model)
        HStack(alignment: .top, spacing: 0) {
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
            VStack(alignment: .leading, spacing: 8 * s) {
                ForEach(running, id: \.self) { item in
                    LiveCard(model: model, item: item, compact: true)
                        .frame(height: 50 * s)
                        .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
                }
                if running.count < 2 {
                    // Under a running clock, its card already says "Timer"; just the presets.
                    TimerSection(model: model, compact: !running.isEmpty, showsHeader: running.isEmpty)
                }
            }
            .sectionFrame()
        case .shortcuts:
            ShortcutsSection(model: model, compact: false)
                .sectionFrame()
        case .timerAndShortcuts:
            VStack(alignment: .leading, spacing: 12 * s) {
                TimerSection(model: model, compact: true)
                ShortcutsSection(model: model, compact: true)
            }
            .sectionFrame()
        }
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
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: (compact ? 12 : 16) * s, style: .continuous)
        Group {
            switch item {
            case .call: LiveCall(model: model, compact: compact)
            case .music: LiveMusic(service: model.nowPlaying, lyrics: model.showsLyrics ? model.lyrics.current : nil, compact: compact)
            case .timer: LiveTimer(model: model)
            case .stopwatch: LiveStopwatch(model: model)
            }
        }
        .padding(.horizontal, (compact ? 8 : 10) * s)
        .padding(.vertical, (compact ? 6 : 10) * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .leading : .topLeading)
        .background(shape.fill(Color.white.opacity(isHovering && opensFullView ? 0.11 : 0.07)))
        .overlay(alignment: .topTrailing) {
            if opensFullView && !compact {
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
        model.activeActivities.contains(item.activity)
    }
}

/// App, what it's doing and for how long, then mute and hang up (or show the app). Compact puts
/// the buttons beside the name.
private struct LiveCall: View {
    let model: IslandModel
    let compact: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        if let session = model.calls.session {
            let tint = session.isCall ? NotchColor.green : NotchColor.orange
            let title = HStack(spacing: 8 * s) {
                AppIconView(icon: model.calls.appIcon, symbol: session.isCall ? "phone.fill" : "mic.fill", tint: tint, size: (compact ? 24 : 30) * s)
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
                .lineLimit(1)
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
                        buttons(session, size: 34 * s)
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
    @Environment(\.notchScale) private var s

    var body: some View {
        let info = service.info
        let playPause = GlyphButton(symbol: info?.isPlaying == true ? "pause.fill" : "play.fill", size: (compact ? 14 : 17) * s, label: info?.isPlaying == true ? "Pause" : "Play") {
            service.togglePlayPause()
        }
        let next = GlyphButton(symbol: "forward.fill", size: 12 * s, label: "Next Track") { service.nextTrack() }
        let title = HStack(spacing: 8 * s) {
            Button { service.openSourceApp() } label: {
                ArtworkView(artwork: service.artwork, fallbackIcon: service.appIcon, size: (compact ? 26 : 40) * s, cornerRadius: (compact ? 6 : 9) * s)
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
            .lineLimit(1)
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
                    if let event = calendar.nextEvent {
                        Text(event.title)
                            .font(.system(size: 13 * s, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        TimelineView(.everyMinute) { context in
                            Text(CalendarRules.relativeLabel(for: event, at: context.date))
                                .font(.system(size: 11 * s, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(event.isHappening(at: context.date) ? NotchColor.green : NotchColor.secondaryText)
                                .lineLimit(1)
                        }
                    } else {
                        message("No more events this week")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text(calendar.nextEvent.map { "Next event, \($0.title)" } ?? "Calendar"))
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
            HStack(spacing: 6 * s) {
                ForEach(TimerService.presets.prefix(3), id: \.self) { preset in
                    Button("\(Int(preset / 60))m") { model.startTimer(preset) }
                        .buttonStyle(QuickActionStyle(tint: NotchColor.orange, scale: s, width: 38 * s))
                        .accessibilityLabel(Text("Start \(TimeFormatting.spoken(preset)) timer"))
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
}

// MARK: Shortcuts

/// The favourite shortcuts, one tap to run. Compact shows only the first.
private struct ShortcutsSection: View {
    let model: IslandModel
    let compact: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            SectionHeader(symbol: "bolt.fill", tint: NotchColor.blue, title: "Shortcuts")
            ForEach(model.favoriteShortcuts.prefix(compact ? 1 : 3), id: \.self) { name in
                let isRunning = model.shortcuts.running.contains(name)
                Button {
                    model.shortcuts.run(name)
                } label: {
                    HStack(spacing: 5 * s) {
                        if isRunning {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(name)
                            .truncationMode(.tail)
                            .frame(maxWidth: 112 * s, alignment: .leading)
                    }
                }
                .buttonStyle(QuickActionStyle(tint: NotchColor.blue, scale: s))
                .disabled(isRunning)
                .help(name)
                .accessibilityLabel(Text("Run shortcut \(name)"))
            }
        }
    }
}
