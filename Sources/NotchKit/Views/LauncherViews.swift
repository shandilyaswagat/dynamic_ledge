import SwiftUI

// MARK: Launcher

/// Everything the notch can do as a grid of tiles, each with its ⌃⌥ shortcut: five to a row,
/// two rows to a page. More tiles make more pages, scrolled through with dots on the right.
struct LauncherBody: View {
    let model: IslandModel
    @State private var page: Int? = 0
    @Environment(\.notchScale) private var s

    nonisolated static let columns = 5
    nonisolated static let rowsPerPage = 2

    var body: some View {
        let pages = Self.pages(model.launcherItems)
        let gap = IslandMetrics.Nook.launcherGap * s
        let columns = Array(repeating: GridItem(.flexible(), spacing: gap), count: Self.columns)
        GeometryReader { geometry in
            HStack(spacing: 10 * s) {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { index in
                            LazyVGrid(columns: columns, spacing: gap) {
                                ForEach(pages[index]) { item in
                                    LauncherTile(model: model, item: item)
                                }
                            }
                            .frame(height: geometry.size.height, alignment: .top)
                            .id(index)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $page)
                if pages.count > 1 {
                    PageDots(count: pages.count, current: page ?? 0) { index in
                        withAnimation(.smooth(duration: 0.35)) { page = index }
                    }
                }
            }
        }
    }

    /// Tiles split into pages of ten.
    nonisolated static func pages(_ items: [LauncherItem]) -> [[LauncherItem]] {
        let size = columns * rowsPerPage
        return stride(from: 0, to: max(items.count, 1), by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }
}

/// A dot per page, the current one bright, like the iPhone's page dots turned on their side.
private struct PageDots: View {
    let count: Int
    let current: Int
    let select: (Int) -> Void
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(spacing: 8 * s) {
            ForEach(0..<count, id: \.self) { index in
                Button { select(index) } label: {
                    Circle()
                        .fill(Color.white.opacity(index == current ? 0.9 : 0.3))
                        .frame(width: 6 * s, height: 6 * s)
                        .frame(width: 14 * s, height: 14 * s)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(Text("Page \(index + 1) of \(count)"))
            }
        }
        .animation(.smooth(duration: 0.25), value: current)
        .frame(maxHeight: .infinity)
    }
}

/// One feature: its icon, its name, and its shortcut in small grey type underneath.
private struct LauncherTile: View {
    let model: IslandModel
    let item: LauncherItem
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        let live = model.isLive(item)
        Button {
            model.open(item)
        } label: {
            VStack(spacing: 0) {
                Image(systemName: Self.symbol(item, live: live))
                    .font(.system(size: 19 * s, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Self.tint(item))
                    .frame(height: 24 * s)
                Text(Self.title(item))
                    .font(.system(size: 11.5 * s, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 7 * s)
                if model.settings.keyboardShortcutsEnabled {
                    Text(item.shortcutLabel)
                        .font(.system(size: 9.5 * s, weight: .regular))
                        .kerning(0.5 * s)
                        .foregroundStyle(Color.white.opacity(0.38))
                        .padding(.top, 2 * s)
                }
            }
            .padding(.horizontal, 6 * s)
            .frame(maxWidth: .infinity)
            .frame(height: IslandMetrics.Nook.launcherTile * s)
            .background(
                RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                    .fill(Color.white.opacity(isHovering ? 0.1 : 0.055))
            )
            .overlay(alignment: .topTrailing) {
                // On right now: music playing, a timer running, kept awake.
                if live {
                    Circle()
                        .fill(Self.tint(item))
                        .frame(width: 6 * s, height: 6 * s)
                        .padding(9 * s)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16 * s, style: .continuous))
            .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(PressableButtonStyle())
        .onHover { isHovering = $0 }
        .help(Self.help(item, live: live))
        .accessibilityLabel(Text(Self.title(item)))
        .accessibilityValue(Text(live ? "On" : ""))
    }

    static func title(_ item: LauncherItem) -> LocalizedStringKey {
        switch item {
        case .nowPlaying: "Now Playing"
        case .timer: "Timer"
        case .stopwatch: "Stopwatch"
        case .calendar: "Calendar"
        case .reminders: "Reminders"
        case .clipboard: "Clipboard"
        case .files: "Files"
        case .scratchpad: "Scratchpad"
        case .mirror: "Camera Mirror"
        case .keepAwake: "Keep Awake"
        case .stats: "Stats"
        }
    }

    static func symbol(_ item: LauncherItem, live: Bool) -> String {
        switch item {
        case .nowPlaying: "music.note"
        case .timer: "timer"
        case .stopwatch: "stopwatch"
        case .calendar: "calendar"
        case .reminders: "checklist"
        case .clipboard: "doc.on.clipboard"
        case .files: "tray.full"
        case .scratchpad: "note.text"
        case .mirror: "web.camera"
        case .keepAwake: live ? "cup.and.heat.waves.fill" : "cup.and.saucer"
        case .stats: "gauge.with.dots.needle.33percent"
        }
    }

    static func tint(_ item: LauncherItem) -> Color {
        switch item {
        case .nowPlaying: Color(red: 1, green: 0.27, blue: 0.4)
        case .timer, .stopwatch: NotchColor.orange
        case .calendar: NotchColor.red
        case .reminders: NotchColor.blue
        case .keepAwake: NotchColor.yellow
        case .stats: NotchColor.green
        default: .white
        }
    }

    static func help(_ item: LauncherItem, live: Bool) -> String {
        switch item {
        case .keepAwake: live ? String(localized: "Your Mac won't sleep. Click to turn off.") : String(localized: "Stop your Mac from going to sleep")
        case .stats: live ? String(localized: "Memory and CPU are showing in the notch. Click to turn off.") : String(localized: "Show memory and CPU in the notch")
        default: ""
        }
    }
}

// MARK: Reminders

/// Today's to-dos. Click the circle to tick one off.
struct RemindersPanelBody: View {
    let model: IslandModel
    @Environment(\.notchScale) private var s

    var body: some View {
        let reminders = model.reminders
        switch reminders.access {
        case .notAsked:
            ConnectPrompt(text: "See today's to-dos from Reminders here.", button: "Connect Reminders", tint: NotchColor.blue) {
                reminders.requestAccess()
            }
        case .denied:
            ConnectPrompt(text: "Reminders access is off for Dynamic Notch.", button: "Open Settings", tint: .white) {
                reminders.openPrivacySettings()
            }
        case .granted:
            if reminders.items.isEmpty {
                VStack(spacing: 6 * s) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 20 * s, weight: .medium))
                    Text("Nothing left for today")
                        .font(.system(size: 12 * s, weight: .medium))
                }
                .foregroundStyle(NotchColor.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 12 * s) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2 * s) {
                            ForEach(reminders.items) { item in
                                ReminderRow(item: item) {
                                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) { reminders.complete(item) }
                                    Haptics.perform(enabled: model.settings.hapticsEnabled)
                                }
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                    }
                    Button("Open Reminders") {
                        reminders.openRemindersApp()
                        model.collapse()
                    }
                    .buttonStyle(ChipButtonStyle(tint: .white, scale: s))
                    .fixedSize()
                }
            }
        }
    }
}

struct ReminderRow: View {
    let item: ReminderItem
    let complete: () -> Void
    @State private var isDone = false
    @Environment(\.notchScale) private var s

    var body: some View {
        HStack(spacing: 10 * s) {
            Button {
                isDone = true
                complete()
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16 * s, weight: .regular))
                    .foregroundStyle(NotchColor.accent(item.color))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("Complete \(item.title)"))
            Text(item.title)
                .font(.system(size: 13 * s, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8 * s)
            TimelineView(.everyMinute) { context in
                if let label = ReminderRules.label(for: item, at: context.date) {
                    Text(label)
                        .font(.system(size: 11 * s, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(label == String(localized: "Overdue") ? NotchColor.red : NotchColor.secondaryText)
                }
            }
        }
        .frame(height: 26 * s)
    }
}

/// A line of text and a button, for features that need a permission first.
struct ConnectPrompt: View {
    let text: LocalizedStringKey
    let button: LocalizedStringKey
    let tint: Color
    let action: () -> Void
    @Environment(\.notchScale) private var s

    var body: some View {
        VStack(spacing: 10 * s) {
            Text(text)
                .font(.system(size: 13 * s, weight: .medium))
                .foregroundStyle(NotchColor.secondaryText)
            Button(button, action: action)
                .buttonStyle(ChipButtonStyle(tint: tint, scale: s))
                .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
