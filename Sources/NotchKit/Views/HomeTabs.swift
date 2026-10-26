import SwiftUI
import UniformTypeIdentifiers

// Home, its tabs (Tray, Clipboard, Notes, Mirror) and its panels (Timer, Calendar) share one
// fixed-size nook (IslandMetrics.Nook): wide and short, widgets side by side. The header sits
// in the strip beside the camera: tabs, or a back button and title for a panel.

// MARK: Container

struct NookContainer<Content: View>: View {
    let model: IslandModel
    let tab: HomeTab
    /// Width of the camera in the middle of the strip.
    let cameraGap: CGFloat
    /// Height of the strip beside the camera.
    let stripHeight: CGFloat
    @ViewBuilder var content: Content
    @Environment(\.notchScale) private var s

    var body: some View {
        let tabs = model.homeTabs
        VStack(spacing: 0) {
            // Each side of the camera gets exactly half of what's left, so nothing can slide
            // under the camera however many tabs are on.
            HStack(spacing: 0) {
                Group {
                    if tab.isPanel {
                        PanelTitle(model: model, title: Self.panelTitle(tab))
                            .padding(.leading, -6 * s)
                    } else {
                        NookTabs(model: model, tabs: tabs, selected: tab)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear
                    .frame(width: cameraGap + 12 * s)
                HStack(spacing: 4 * s) {
                    UpdatePill(model: model)
                    LauncherButton(model: model, isOpen: tab == .launcher)
                    SettingsButton(model: model)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: stripHeight)
            .padding(.bottom, IslandMetrics.notchContentGap)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, (IslandMetrics.Nook.bodyTopInset * s).rounded())
        }
        .padding(.horizontal, 20 * s)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private static func panelTitle(_ tab: HomeTab) -> LocalizedStringKey {
        switch tab {
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .notes: "Scratchpad"
        case .mirror: "Camera Mirror"
        case .stats: "Stats"
        default: "Timer"
        }
    }
}

/// Back to Home, then the panel's name.
private struct PanelTitle: View {
    let model: IslandModel
    let title: LocalizedStringKey
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 3 * s) {
            BackToHomeButton(model: model)
            Text(title)
                .font(.system(size: 13 * s, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}

/// Back to Home, drawn the way macOS draws toolbar back buttons: a plain chevron that gets a soft
/// round highlight under the pointer. Used on panels and on every activity's expanded view.
struct BackToHomeButton: View {
    let model: IslandModel
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        Button {
            model.showTab(.home)
        } label: {
            Image(systemName: "chevron.backward")
                .font(.system(size: 13 * s, weight: .semibold))
                .foregroundStyle(.white.opacity(isHovering ? 1 : 0.85))
                .frame(width: 24 * s, height: 24 * s)
                .background(Circle().fill(Color.white.opacity(isHovering ? 0.14 : 0)))
                .contentShape(Circle())
                .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
        .help("Home")
        .accessibilityLabel(Text("Back to Home"))
    }
}

/// Shows up beside the grid button when a new version is out: one click installs it and
/// relaunches (or opens the download page when this copy can't update itself).
private struct UpdatePill: View {
    let model: IslandModel
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        let updater = model.updater
        Group {
            switch updater.state {
            case .available(let release):
                let installs = updater.canInstallInPlace(release)
                Button { updater.install(release) } label: {
                    Label(installs ? "Update" : "Download", systemImage: "arrow.down.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11 * s, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9 * s)
                        .frame(height: 22 * s)
                        .background(Capsule().fill(NotchColor.blue))
                        .brightness(isHovering ? 0.08 : 0)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .onHover { isHovering = $0 }
                .help(installs
                      ? "Version \(release.version.description) is out. Click to install it and relaunch."
                      : "Version \(release.version.description) is out. Click to download it.")
                .accessibilityLabel(Text("Update to version \(release.version.description)"))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            case .installing:
                HStack(spacing: 5 * s) {
                    ProgressView().controlSize(.mini)
                    Text("Updating…")
                }
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundStyle(NotchColor.secondaryText)
                .padding(.horizontal, 9 * s)
                .frame(height: 22 * s)
                .background(Capsule().fill(NotchColor.buttonFill))
                .transition(.opacity)
            default:
                EmptyView()
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.3), value: updater.state)
    }
}

/// The grid of everything the notch can do, next to Settings.
private struct LauncherButton: View {
    let model: IslandModel
    let isOpen: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        Button {
            if isOpen { model.showTab(.home) } else { model.showTab(.launcher) }
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(isOpen ? .white : NotchColor.secondaryText)
                .frame(width: 26 * s, height: 22 * s)
                .background(Capsule().fill(isOpen ? NotchColor.buttonFill : .clear))
        }
        .buttonStyle(PressableButtonStyle())
        .help("Everything")
        .accessibilityLabel(Text("All features"))
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }
}

/// A row of tabs. The selected tab shows its name when there's room; if there isn't, every tab
/// is just an icon, so the row never runs into the camera.
private struct NookTabs: View {
    let model: IslandModel
    let tabs: [HomeTab]
    let selected: HomeTab

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(showsTitle: true)
            row(showsTitle: false)
        }
    }

    private func row(showsTitle: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(tabs, id: \.self) { tab in
                NookTabButton(model: model, tab: tab, isSelected: tab == selected, showsTitle: showsTitle)
            }
        }
        .fixedSize()
    }
}

private struct NookTabButton: View {
    let model: IslandModel
    let tab: HomeTab
    let isSelected: Bool
    let showsTitle: Bool
    @Environment(\.notchScale) private var s

    var body: some View {
        Button {
            model.showTab(tab)
        } label: {
            HStack(spacing: 4 * s) {
                Image(systemName: Self.symbol(tab))
                    .font(.system(size: 11 * s, weight: .semibold))
                if isSelected, showsTitle {
                    Text(Self.title(tab))
                        .font(.system(size: 11 * s, weight: .semibold))
                }
                if tab == .tray, !model.tray.items.isEmpty {
                    Text("\(model.tray.items.count)")
                        .font(.system(size: 9 * s, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? .black : .white)
                        .padding(.horizontal, 4 * s)
                        .background(Capsule().fill(isSelected ? Color.white : NotchColor.buttonFill))
                }
            }
            .foregroundStyle(isSelected ? .white : NotchColor.secondaryText)
            .padding(.horizontal, 8 * s)
            .frame(height: 22 * s)
            .background(Capsule().fill(isSelected ? NotchColor.buttonFill : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .help(Text(Self.title(tab)))
        .accessibilityLabel(Text(Self.title(tab)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    static func title(_ tab: HomeTab) -> LocalizedStringKey {
        switch tab {
        case .home: "Home"
        case .tray: "Tray"
        case .clipboard: "Clipboard"
        case .notes: "Notes"
        case .mirror: "Mirror"
        case .timers: "Timer"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .stats: "Stats"
        case .launcher: "All Features"
        }
    }

    static func symbol(_ tab: HomeTab) -> String {
        switch tab {
        case .home: "house.fill"
        case .tray: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .notes: "note.text"
        case .mirror: "person.crop.square.fill"
        case .timers: "timer"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .stats: "gauge.with.dots.needle.33percent"
        case .launcher: "square.grid.2x2"
        }
    }
}

/// Settings, at the far right of the strip.
private struct SettingsButton: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        Button {
            model.collapse()
            model.onOpenSettings?()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(NotchColor.secondaryText)
                .frame(width: 22 * s, height: 22 * s)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("Settings"))
        .help("Settings")
    }
}

// MARK: Home

/// Media card on the left; calendar, timers and shortcuts beside it.
struct HomeBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        if model.settings.appearance.nookLayout == .elongated {
            ElongatedHomeBody(model: model)
        } else {
            standard
        }
    }

    private var standard: some View {
        let content = model.homeContent
        return HStack(alignment: .top, spacing: 14 * s) {
            if content.hasMedia {
                MediaCard(service: model.nowPlaying)
                    .frame(width: IslandMetrics.Nook.mediaCardWidth * s)
                    .frame(maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: IslandMetrics.Nook.rowGap * s) {
                if content.hasEvent {
                    CalendarRow(model: model, calendar: model.calendar)
                        .frame(height: IslandMetrics.Nook.row * s)
                }
                if content.hasTimer {
                    TimerPresetsRow(model: model)
                        .frame(height: IslandMetrics.Nook.row * s)
                }
                if content.hasShortcuts {
                    ShortcutsRow(model: model)
                        .frame(height: IslandMetrics.Nook.row * s)
                }
                if content.rowCount == 0 && !content.hasMedia {
                    Text("Nothing live right now")
                        .font(.system(size: 13 * s, weight: .medium))
                        .foregroundStyle(NotchColor.secondaryText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.bottom, 2 * s)
    }
}

/// Artwork, title and transport controls in a small card.
private struct MediaCard: View {
    let service: NowPlayingService
    @Environment(\.notchScale) private var s

    var body: some View {
        let info = service.info
        VStack(alignment: .leading, spacing: 8 * s) {
            HStack(spacing: 10 * s) {
                Button { service.openSourceApp() } label: {
                    ArtworkView(artwork: service.artwork, fallbackIcon: service.appIcon, size: 46 * s, cornerRadius: 10 * s)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("Open player"))
                VStack(alignment: .leading, spacing: 2 * s) {
                    Text(info?.title ?? "")
                        .font(.system(size: 13 * s, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(info?.artist.isEmpty == false ? info?.artist ?? "" : service.appName ?? "")
                        .font(.system(size: 11 * s))
                        .foregroundStyle(NotchColor.secondaryText)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            MiniProgress(service: service)
                .frame(height: 3 * s)
            HStack(spacing: 18 * s) {
                GlyphButton(symbol: "backward.fill", size: 13 * s, label: "Previous Track") { service.previousTrack() }
                GlyphButton(symbol: info?.isPlaying == true ? "pause.fill" : "play.fill", size: 18 * s, label: info?.isPlaying == true ? "Pause" : "Play") {
                    service.togglePlayPause()
                }
                GlyphButton(symbol: "forward.fill", size: 13 * s, label: "Next Track") { service.nextTrack() }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(10 * s)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 16 * s, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

struct MiniProgress: View {
    let service: NowPlayingService

    var body: some View {
        let info = service.info
        TimelineView(.animation(minimumInterval: 1, paused: info?.isPlaying != true)) { context in
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule().fill(Color.white.opacity(0.85))
                        .frame(width: geometry.size.width * (info?.progress(at: context.date) ?? 0))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// The next event, or a button to connect the calendar the first time.
private struct CalendarRow: View {
    let model: IslandModel
    let calendar: CalendarService
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 8 * s) {
            switch calendar.access {
            case .notAsked:
                RowLabel(symbol: "calendar", tint: NotchColor.red, title: "Calendar")
                Spacer(minLength: 8 * s)
                Button("Connect") { calendar.requestAccess() }
                    .buttonStyle(QuickActionStyle(tint: NotchColor.red, scale: s))
            case .denied, .limited:
                RowLabel(symbol: "calendar", tint: NotchColor.red, title: "Calendar")
                Spacer(minLength: 8 * s)
                Button("Allow Access") { calendar.openPrivacySettings() }
                    .buttonStyle(QuickActionStyle(tint: NotchColor.red, scale: s))
                    .help("Turn on Dynamic Notch in Privacy & Security › Calendars")
            case .granted:
                // Always shown once connected, even on a free day, and always opens the month.
                Button { model.showTab(.calendar) } label: {
                    HStack(spacing: 8 * s) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12 * s, weight: .semibold))
                            .foregroundStyle(NotchColor.red)
                            .frame(width: 16 * s)
                        if let event = calendar.nextEvent {
                            Text(event.title)
                                .font(.system(size: 12 * s, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer(minLength: 6 * s)
                            TimelineView(.everyMinute) { context in
                                Text(CalendarRules.relativeLabel(for: event, at: context.date))
                                    .font(.system(size: 11 * s, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(event.isHappening(at: context.date) ? NotchColor.green : NotchColor.secondaryText)
                                    .fixedSize()
                            }
                        } else {
                            Text("No more events this week")
                                .font(.system(size: 12 * s, weight: .medium))
                                .foregroundStyle(NotchColor.secondaryText)
                                .lineLimit(1)
                            Spacer(minLength: 6 * s)
                        }
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 9 * s, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.3))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text(calendar.nextEvent.map { "Next event, \($0.title)" } ?? "Calendar"))
            }
        }
    }
}

/// The start of a Home row: a tinted symbol and a name, like a row in an Apple list.
private struct RowLabel: View {
    let symbol: String
    let tint: Color
    let title: LocalizedStringKey
    var showsChevron = false
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 8 * s) {
            Image(systemName: symbol)
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16 * s)
            Text(title)
                .font(.system(size: 12 * s, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
            if showsChevron {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 9 * s, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
        }
    }
}

/// A small quick-action capsule on the right of a Home row: soft grey fill, tinted label, every
/// one the same type size (no shrinking to fit).
struct QuickActionStyle: ButtonStyle {
    var tint: Color
    var scale: CGFloat
    var width: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        QuickActionLabel(configuration: configuration, tint: tint, scale: scale, width: width)
    }
}

private struct QuickActionLabel: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    let scale: CGFloat
    let width: CGFloat?
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 12 * scale, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 9 * scale)
            .frame(minWidth: width, minHeight: 26 * scale, maxHeight: 26 * scale)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.2 : (isHovering ? 0.14 : 0.09))))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .onHover { isHovering = $0 }
            .fixedSize()
    }
}

/// "Timer ›" opens the full timer; the capsules on the right start one straight away.
private struct TimerPresetsRow: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 6 * s) {
            Button {
                model.timerPanelMode = .timer
                model.showTab(.timers)
            } label: {
                RowLabel(symbol: "timer", tint: NotchColor.orange, title: "Timer", showsChevron: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .help("Any length, Pomodoro or Stopwatch")
            .accessibilityLabel(Text("Timer"))
            Spacer(minLength: 8 * s)
            ForEach(TimerService.presets.prefix(3), id: \.self) { preset in
                Button(Self.shortLabel(preset)) { model.startTimer(preset) }
                    .buttonStyle(QuickActionStyle(tint: NotchColor.orange, scale: s, width: 40 * s))
                    .accessibilityLabel(Text("Start \(TimeFormatting.spoken(preset)) timer"))
            }
            Button {
                model.startSession(.focus)
            } label: {
                Label("Focus", systemImage: TimerMode.focus.symbol)
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(QuickActionStyle(tint: NotchColor.orange, scale: s))
            .help("Focus for \(model.settings.focusMinutes) minutes, then take a \(model.settings.breakMinutes) minute break")
            .accessibilityLabel(Text("Start a \(model.settings.focusMinutes) minute focus session"))
        }
    }

    /// "5m", "10m": short enough that the row fits beside the music card.
    private static func shortLabel(_ seconds: TimeInterval) -> String {
        "\(Int(seconds / 60))m"
    }
}

private struct ShortcutsRow: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 6 * s) {
            RowLabel(symbol: "bolt.fill", tint: NotchColor.blue, title: "Shortcuts")
            Spacer(minLength: 8 * s)
            ForEach(model.favoriteShortcuts, id: \.self) { name in
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
                            .frame(maxWidth: 110 * s)
                    }
                }
                .buttonStyle(QuickActionStyle(tint: NotchColor.blue, scale: s))
                .disabled(isRunning)
                .accessibilityLabel(Text("Run shortcut \(name)"))
            }
        }
    }
}

// MARK: Tray

/// Files dropped on the notch. Drag them out, double-click to open, right-click for more.
struct TrayBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            if let message = model.tray.statusMessage {
                Text(message)
                    .font(.system(size: 10 * s))
                    .foregroundStyle(.orange)
            }
            contents
        }
    }

    @ViewBuilder private var contents: some View {
        let items = model.tray.items
        if items.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                VStack(spacing: 6 * s) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 22 * s, weight: .semibold))
                    Text("Drag files onto the notch to keep them here")
                        .font(.system(size: 13 * s, weight: .medium))
                    Text("They stay here until you quit. Your originals aren't touched.")
                        .font(.system(size: 10 * s))
                }
                .foregroundStyle(NotchColor.secondaryText)
            }
            .padding(.bottom, 2 * s)
        } else {
            HStack(alignment: .center, spacing: 8 * s) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6 * s) {
                        ForEach(items) { item in
                            TrayItemView(model: model, item: item)
                        }
                    }
                }
                Button {
                    model.tray.removeAll()
                } label: {
                    Image(systemName: "xmark.bin.fill")
                        .font(.system(size: 12 * s, weight: .semibold))
                        .foregroundStyle(NotchColor.secondaryText)
                        .frame(width: 28 * s, height: 28 * s)
                        .background(Circle().fill(NotchColor.buttonFill))
                }
                .buttonStyle(PressableButtonStyle())
                .help("Clear the tray")
                .accessibilityLabel(Text("Clear the tray"))
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct TrayItemView: View {
    let model: IslandModel
    let item: TrayStore.Item
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(spacing: 5 * s) {
            Image(nsImage: model.tray.icon(for: item))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 52 * s, height: 52 * s)
            Text(item.name)
                .font(.system(size: 10 * s, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 70 * s)
        }
        .padding(6 * s)
        .background(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).fill(Color.white.opacity(isHovering ? 0.12 : 0)))
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button { model.tray.remove(item.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14 * s))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(white: 0.35))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("Remove \(item.name)"))
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        // Double-click opens, like Finder.
        .onTapGesture(count: 2) { model.tray.open(item) }
        .onDrag {
            model.isDraggingFromTray = true
            return NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Open") { model.tray.open(item) }
            Button("Show in Finder") { model.tray.revealInFinder(item) }
            Button("Send with AirDrop") { model.airDrop([item.url]) }
            Divider()
            Button("Remove from Tray") { model.tray.remove(item.id) }
        }
        .help(item.name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(item.name))
    }
}

// MARK: Mirror

/// A quick look at your camera before a call.
struct MirrorBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 16 * s) {
            ZStack {
                RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                if model.camera.state == .granted {
                    CameraPreview()
                        .clipShape(RoundedRectangle(cornerRadius: 16 * s, style: .continuous))
                } else {
                    Image(systemName: "person.crop.square.fill")
                        .font(.system(size: 28 * s, weight: .medium))
                        .foregroundStyle(NotchColor.secondaryText)
                }
            }
            // 16:9, the shape of a video call.
            .aspectRatio(16 / 9, contentMode: .fit)
            VStack(alignment: .leading, spacing: 8 * s) {
                Text(Self.message(model.camera.state))
                    .font(.system(size: 12 * s, weight: .medium))
                    .foregroundStyle(NotchColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                switch model.camera.state {
                case .notAsked:
                    Button("Turn On Camera") { model.camera.request() }
                        .buttonStyle(ChipButtonStyle(tint: .white, scale: s))
                        .fixedSize()
                case .denied:
                    Button("Open Settings") { model.camera.openPrivacySettings() }
                        .buttonStyle(ChipButtonStyle(tint: .white, scale: s))
                        .fixedSize()
                case .granted, .noCamera:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 2 * s)
    }

    private static func message(_ state: CameraAccess.State) -> LocalizedStringKey {
        switch state {
        case .granted: "Check how you look before a call. The camera turns off when you close this."
        case .notAsked: "Check how you look before a call."
        case .denied: "Camera access is off for Dynamic Notch."
        case .noCamera: "No camera found."
        }
    }
}
