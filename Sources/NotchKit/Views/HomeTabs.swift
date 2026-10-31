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
        VStack(spacing: 0) {
            // Each side of the camera gets exactly half of what's left, so nothing can slide
            // under the camera however many tabs are on.
            HStack(spacing: 0) {
                Group {
                    if tab.isPanel {
                        PanelTitle(model: model, title: Self.panelTitle(tab))
                            // Calendar and the other panels keep a dedicated leading slot for
                            // the Home control, rather than squeezing it against the title.
                            .frame(minWidth: 112 * s, alignment: .leading)
                            .padding(.leading, 2 * s)
                    } else {
                        FeatureShortcutBar(model: model, selectedTab: tab)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear
                    .frame(width: cameraGap + 12 * s)
                HStack(spacing: 4 * s) {
                    if model.isEditingShortcuts {
                        // How many are picked, so the limit is clear before it's hit.
                        Text("\(model.featureShortcuts.count) of \(SettingsStore.maximumFeatureShortcuts)")
                            .font(.system(size: 11 * s, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(NotchColor.secondaryText)
                            .padding(.trailing, 4 * s)
                            .help("Click features to add them beside Home, or a ticked one to remove it")
                        DoneButton { model.isEditingShortcuts = false }
                            .accessibilityLabel(Text("Done editing shortcuts"))
                    } else {
                        UpdatePill(model: model)
                        LauncherButton(model: model, isOpen: tab == .launcher)
                        SettingsButton(model: model)
                    }
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
/// relaunches (or opens the download page when this copy can't update itself). A fresh update
/// opens as an "Update" pill, then shrinks to a round download button after a moment; pointing
/// at it brings the label back.
private struct UpdatePill: View {
    let model: IslandModel
    @State private var showsLabel = false
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    /// How long the full pill stays before it shrinks.
    private static let labelTime: Duration = .seconds(3.5)

    var body: some View {
        let updater = model.updater
        Group {
            switch updater.state {
            case .available(let release):
                let installs = updater.canInstallInPlace(release)
                let expanded = showsLabel || isHovering
                Button { updater.install(release) } label: {
                    HStack(spacing: 4 * s) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11 * s, weight: .heavy))
                        if expanded {
                            Text(installs ? "Update" : "Download")
                                .font(.system(size: 11 * s, weight: .semibold))
                                .fixedSize()
                                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                        }
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, expanded ? 9 * s : 0)
                    .frame(minWidth: 22 * s, minHeight: 22 * s)
                    .background(Capsule().fill(Color.white))
                    .brightness(isHovering ? -0.06 : 0)
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .onHover { isHovering = $0 }
                .animation(.spring(duration: 0.4, bounce: 0.2), value: expanded)
                .help(installs
                      ? "Version \(release.version.description) is out. Click to install it and relaunch."
                      : "Version \(release.version.description) is out. Click to download it.")
                .accessibilityLabel(Text("Update to version \(release.version.description)"))
                .transition(.scale(scale: 0.6).combined(with: .opacity))
                .task(id: release.version.description) {
                    guard updater.isUpdateRecent else { return }
                    showsLabel = true
                    try? await Task.sleep(for: Self.labelTime)
                    showsLabel = false
                }
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

/// The permanent Home button and up to three saved feature shortcuts in the top-left corner,
/// in the order they were added. While the grid is editing, each shows a remove badge.
private struct FeatureShortcutBar: View {
    let model: IslandModel
    let selectedTab: HomeTab
    @Environment(\.notchScale) private var s

    var body: some View {
        let shortcuts = model.featureShortcuts
        let isEditing = model.isEditingShortcuts
        HStack(spacing: 3 * s) {
            HomeShortcutButton(isSelected: selectedTab == .home && !isEditing) {
                model.isEditingShortcuts = false
                model.showTab(.home)
            }
            ForEach(shortcuts) { item in
                CustomShortcutButton(
                    item: item,
                    isSelected: isCurrentFeature(item) && !isEditing,
                    isEditing: isEditing,
                    badge: item == .files && !isEditing ? model.tray.items.count : 0,
                    onTap: {
                        if isEditing { remove(item) } else { model.open(item) }
                    },
                    onRemove: { remove(item) }
                )
            }
        }
        .padding(2 * s)
        .background(Capsule().fill(Color.white.opacity(0.055)))
        .contentShape(Capsule())
        .accessibilityIdentifier("feature-shortcuts")
        .animation(.spring(duration: 0.3, bounce: 0.2), value: shortcuts)
    }

    private func remove(_ item: LauncherItem) {
        model.settings.removeFeatureShortcut(item)
        Haptics.perform(enabled: model.settings.hapticsEnabled)
    }

    private func isCurrentFeature(_ item: LauncherItem) -> Bool {
        switch item {
        case .nowPlaying: model.presentation == .expanded(.nowPlaying)
        case .timer: selectedTab == .timers && model.timerPanelMode == .timer
        case .stopwatch: selectedTab == .timers && model.timerPanelMode == .stopwatch
        case .calendar: selectedTab == .calendar
        case .reminders: selectedTab == .reminders
        case .clipboard: selectedTab == .clipboard
        case .files: selectedTab == .tray
        case .scratchpad: selectedTab == .notes
        case .mirror: selectedTab == .mirror
        case .keepAwake: model.keepAwake.isOn
        case .stats: selectedTab == .stats
        }
    }
}

private struct HomeShortcutButton: View {
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        // Fixed in place: a click opens Home, holding it does nothing.
        Image(systemName: "house.fill")
            .font(.system(size: 11 * s, weight: .semibold))
            .foregroundStyle(isSelected ? .white : NotchColor.secondaryText)
            .frame(width: 24 * s, height: 22 * s)
            .background(Circle().fill(isSelected ? NotchColor.buttonFill : (isHovering ? Color.white.opacity(0.08) : Color.clear)))
            .contentShape(Circle())
            .modifier(ClickNotHold(onClick: action))
        .onHover { isHovering = $0 }
        .help("Home")
        .accessibilityLabel(Text("Home"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CustomShortcutButton: View {
    let item: LauncherItem
    let isSelected: Bool
    let isEditing: Bool
    /// A count shown on the icon: how many files are in the Tray.
    let badge: Int
    let onTap: () -> Void
    let onRemove: () -> Void
    @State private var isHovering = false
    @Environment(\.notchScale) private var s

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Fixed in place: a click opens the feature (or removes it while editing), holding
            // it does nothing and it can't be dragged.
            Image(systemName: item.symbolName)
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundStyle(isSelected ? .white : NotchColor.secondaryText)
                .frame(width: 24 * s, height: 22 * s)
                .background(Circle().fill(isSelected ? NotchColor.buttonFill : (isHovering ? Color.white.opacity(0.08) : Color.clear)))
                .contentShape(Circle())
                .modifier(ClickNotHold(onClick: onTap))
            .onHover { isHovering = $0 }
            .help(isEditing ? "Remove \(item.title)" : item.title)
            .accessibilityLabel(Text(item.title))
            .accessibilityValue(Text(badge > 0 ? "\(badge)" : ""))
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            if isEditing {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 10 * s, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, NotchColor.red)
                        .frame(width: 14 * s, height: 14 * s)
                        .background(Circle().fill(Color.black.opacity(0.8)))
                }
                .buttonStyle(PlainButtonStyle())
                .offset(x: 3 * s, y: -3 * s)
                .accessibilityLabel(Text("Remove \(item.title)"))
            } else if badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 8 * s, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3 * s)
                    .frame(minWidth: 12 * s, minHeight: 12 * s)
                    .background(Capsule().fill(NotchColor.blue))
                    .offset(x: 3 * s, y: -2 * s)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAction(named: Text("Remove")) { onRemove() }
    }
}

/// Ends editing the shortcuts, at the top right while the grid is in edit mode.
private struct DoneButton: View {
    let action: () -> Void
    @Environment(\.notchScale) private var s

    var body: some View {
        Button(action: action) {
            Text("Done")
                .font(.system(size: 11 * s, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10 * s)
                .frame(height: 22 * s)
                .background(Capsule().fill(NotchColor.blue))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableButtonStyle())
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

/// Up to three sections side by side (HomeSections.swift), or the elongated row of widgets.
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
        StandardHomeBody(model: model)
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
        let items = model.tray.ordered
        if items.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 16 * s, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                VStack(spacing: 6 * s) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 22 * s, weight: .semibold))
                    Text("Drag files onto the notch to keep them here")
                        .font(.system(size: 13 * s, weight: .medium))
                    Text("They stay until you quit, or pin one to keep it. Your originals aren't touched.")
                        .font(.system(size: 10 * s))
                }
                .foregroundStyle(NotchColor.secondaryText)
            }
            .padding(.bottom, 2 * s)
        } else {
            HStack(alignment: .center, spacing: 12 * s) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12 * s) {
                        ForEach(items) { item in
                            TrayItemView(model: model, item: item)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 4 * s)
                    .padding(.top, 8 * s)
                    .padding(.bottom, 6 * s)
                }
                Button {
                    withAnimation(.snappy(duration: 0.25)) { model.tray.removeAll() }
                } label: {
                    Image(systemName: "xmark.bin.fill")
                        .font(.system(size: 13 * s, weight: .semibold))
                        .foregroundStyle(NotchColor.secondaryText)
                        .frame(width: 28 * s, height: 28 * s)
                        .background(Circle().fill(NotchColor.buttonFill))
                }
                .buttonStyle(PressableButtonStyle())
                .help(model.tray.pinnedCount > 0 ? "Clear the tray (pinned items stay)" : "Clear the tray")
                .accessibilityLabel(Text("Clear the tray"))
                // Clearing leaves pinned items, so it's only offered when there's something else.
                .disabled(model.tray.pinnedCount == items.count)
                .opacity(model.tray.pinnedCount == items.count ? 0.4 : 1)
            }
            .frame(maxHeight: .infinity)
            .animation(.snappy(duration: 0.25), value: items.map(\.id))
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
                .frame(width: 48 * s, height: 48 * s)
            Text(item.name)
                .font(.system(size: 10 * s, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 72 * s)
        }
        .padding(.horizontal, 8 * s)
        .padding(.vertical, 8 * s)
        .background(RoundedRectangle(cornerRadius: 12 * s, style: .continuous).fill(Color.white.opacity(isHovering ? 0.12 : (item.isPinned ? 0.06 : 0))))
        .overlay(alignment: .topLeading) {
            // Pinned items always show the pin; on hover, any item offers it.
            if item.isPinned || isHovering {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { model.tray.togglePin(item.id) }
                } label: {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 9.5 * s, weight: .bold))
                        .foregroundStyle(item.isPinned ? NotchColor.orange : .white.opacity(0.85))
                        .frame(width: 18 * s, height: 18 * s)
                        .background(Circle().fill(Color.black.opacity(0.75)))
                        .frame(width: 22 * s, height: 22 * s)
                        .contentShape(Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .padding([.top, .leading], 3 * s)
                .help(item.isPinned ? "Unpin" : "Pin, so it stays after you quit")
                .accessibilityLabel(Text(item.isPinned ? "Unpin \(item.name)" : "Pin \(item.name)"))
            }
        }
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button { model.tray.remove(item.id) } label: {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.75))
                            .frame(width: 18 * s, height: 18 * s)
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15 * s))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color(white: 0.35))
                    }
                    .frame(width: 22 * s, height: 22 * s)
                    .contentShape(Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .padding([.top, .trailing], 3 * s)
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
            Button(item.isPinned ? "Unpin" : "Pin") { model.tray.togglePin(item.id) }
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
                if model.camera.state == .granted && !model.camera.isCameraOff {
                    CameraPreview()
                        .clipShape(RoundedRectangle(cornerRadius: 16 * s, style: .continuous))
                } else {
                    Image(systemName: model.camera.isCameraOff ? "camera.slash.fill" : "person.crop.square.fill")
                        .font(.system(size: 28 * s, weight: .medium))
                        .foregroundStyle(NotchColor.secondaryText)
                }
            }
            // 16:9, the shape of a video call.
            .aspectRatio(16 / 9, contentMode: .fit)
            VStack(alignment: .leading, spacing: 8 * s) {
                Text(Self.message(model.camera.state, isOff: model.camera.isCameraOff))
                    .font(.system(size: 12 * s, weight: .medium))
                    .foregroundStyle(NotchColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                switch model.camera.state {
                case .notAsked:
                    Button("Turn On Camera") {
                        model.camera.isCameraOff = false
                        model.camera.request()
                    }
                    .buttonStyle(ChipButtonStyle(tint: .white, scale: s))
                    .fixedSize()
                case .denied:
                    Button("Open Settings") { model.camera.openPrivacySettings() }
                        .buttonStyle(ChipButtonStyle(tint: .white, scale: s))
                        .fixedSize()
                case .granted:
                    Button(model.camera.isCameraOff ? "Turn On Camera" : "Turn Off Camera") {
                        model.camera.toggleCamera()
                    }
                    .buttonStyle(ChipButtonStyle(tint: .white, scale: s))
                    .fixedSize()
                    .accessibilityLabel(Text(model.camera.isCameraOff ? "Turn on camera" : "Turn off camera"))
                case .noCamera:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 2 * s)
    }

    private static func message(_ state: CameraAccess.State, isOff: Bool) -> LocalizedStringKey {
        switch state {
        case .granted:
            isOff
                ? "Camera preview is turned off."
                : "Check how you look before a call. The camera turns off when you close this."
        case .notAsked: "Check how you look before a call."
        case .denied: "Camera access is off for Dynamic Ledge."
        case .noCamera: "No camera found."
        }
    }
}
