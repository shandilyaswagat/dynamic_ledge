import SwiftUI

/// Everything inside the island window.
struct IslandRootView: View {
    let model: IslandModel
    /// The screen this window is on. Only the screen in use shows what's opened.
    let display: DisplayContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What was showing before the latest change, so closing can use a spring that doesn't bounce.
    @State private var previous: IslandPresentation?

    var body: some View {
        let presentation = model.presentation(onDisplay: display.id)
        let layout = model.layout(onDisplay: display.id, metrics: display.metrics)
        let liquid = model.settings.liquidAnimations && !reduceMotion
        let appearance = model.settings.appearance

        ZStack(alignment: .topLeading) {
            // Only the bubble splitting off (or merging back) melts; the notch itself keeps crisp
            // edges as it opens and closes.
            if appearance.theme == .glass {
                GlassSurface(
                    layout: layout,
                    tint: appearance.glassTint,
                    prepared: model.isHoveringPill || model.isHoveringNotch || presentation.isExpandedFamily
                )
                    .frame(width: layout.canvasSize.width, height: layout.canvasSize.height, alignment: .topLeading)
            } else {
                KeyframeAnimator(initialValue: 0.0, trigger: presentation.topology.split) { pulse in
                    IslandSurface(layout: layout, pulse: pulse, liquid: liquid)
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(1, duration: 0.08)
                        SpringKeyframe(0, duration: 0.6, spring: .smooth)
                    }
                }
                .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
            }

            IslandContentLayer(model: model, presentation: presentation, layout: layout)
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height, alignment: .topLeading)
        .animation(Motion.shape(from: previous, to: presentation, reduceMotion: reduceMotion, theme: appearance.theme, style: model.settings.motionStyle), value: presentation)
        .onChange(of: presentation, initial: true) { _, new in previous = new }
        .animation(Motion.settings, value: model.settings.appearance)
        // Lyrics arriving, a second app playing, Clipboard's search bar: the shape eases to fit.
        .animation(reduceMotion ? nil : Motion.resize(appearance.theme, style: model.settings.motionStyle), value: model.homeContent)
        .animation(reduceMotion ? nil : Motion.hover(appearance.theme, style: model.settings.motionStyle), value: model.isHoveringPill)
        .environment(\.colorScheme, .dark)
        // No scroll bars anywhere in the notch, even when macOS shows them because a mouse is
        // connected: they'd cover content and squeeze narrow lists like the timer's wheels.
        .scrollIndicators(.never)
        // The panel is intentionally non-activating, so publish a stable action while it is
        // tucked away. This keeps Voice Control and automation able to open the same Home view
        // that a click on the notch opens without changing the panel's mouse routing.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Dynamic Ledge"))
        .accessibilityAction(named: Text("Open Home")) { model.showTab(.home) }
    }
}

/// Content clipped to the animating pill and bubble.
struct IslandContentLayer: View {
    let model: IslandModel
    let presentation: IslandPresentation
    let layout: IslandLayout
    /// Home or one of its tabs was already open before this render. Switching between them keeps
    /// the shape still, so the content just crossfades instead of growing out of the notch again.
    @State private var nookWasOpen = false
    /// What an open view resizes to fit in place: lyrics arriving, a search bar, a settings change.
    /// While it does, the content keeps its size instead of growing with the shape, so it doesn't
    /// zoom. Opening and closing always grow and shrink it with the shape.
    @State private var resizeKey: ResizeKey?
    @State private var isResizing = false
    @State private var resizeEnd: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .topLeading) {
            pill
            bubble
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height, alignment: .topLeading)
        .onChange(of: presentation.homeTab != nil, initial: true) { _, isOpen in nookWasOpen = isOpen }
        .onChange(of: currentResizeKey, initial: true) { old, new in
            resizeKey = new
            guard old != new else { return }
            isResizing = true
            resizeEnd?.cancel()
            resizeEnd = Task {
                try? await Task.sleep(for: .seconds(StretchWithShell.resizeDuration))
                guard !Task.isCancelled else { return }
                isResizing = false
            }
        }
    }

    private var currentResizeKey: ResizeKey {
        ResizeKey(home: model.homeContent, appearance: model.settings.appearance)
    }

    /// True from the very render that changes the size, before `onChange` has run.
    private var resizesInPlace: Bool {
        isResizing || (resizeKey != nil && resizeKey != currentResizeKey)
    }

    private var pillShape: IslandShape {
        IslandShape(topRadius: layout.topRadius, bottomRadius: layout.bottomRadius, flare: layout.flare)
    }

    private var pill: some View {
        ZStack(alignment: .topLeading) {
            if presentation.isVisible {
                let resting = layout.restingPill
                NotchContent(model: model, presentation: presentation, size: layout.content.size, cameraGap: layout.cameraGap, stripHeight: layout.stripHeight)
                    .environment(\.notchScale, layout.contentScale)
                    .frame(width: layout.content.width, height: layout.content.height)
                    .offset(x: layout.content.minX - resting.minX, y: layout.content.minY - resting.minY)
                    .frame(width: max(resting.width, 1), height: max(resting.height, 1), alignment: .topLeading)
                    .modifier(StretchWithShell(
                        resting: resting.size,
                        isOpenView: Motion.isOpenView(presentation),
                        stretches: !resizesInPlace
                    ))
                    .id(ContentKey(presentation))
                    .transition(contentTransition)
            }
        }
        .overlay(alignment: .topLeading) {
            // In the strip beside the camera.
            if case .expanded = presentation {
                // Only the part of the strip left of the camera, so the name never slides under it.
                let leading = layout.flare + 14 * layout.contentScale
                let room = (layout.pill.width - model.engine.cameraGap) / 2 - leading - 8 * layout.contentScale
                ActivityHeader(model: model, presentation: presentation)
                    .environment(\.notchScale, layout.contentScale)
                    .frame(width: max(room, 1), alignment: .leading)
                    .padding(.leading, leading)
                    .frame(height: max(layout.content.minY - layout.pill.minY, 1))
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            // The other live activities, right of the camera, to switch to.
            if case .expanded(let kind) = presentation {
                ActivitySwitcher(model: model, current: kind)
                    .environment(\.notchScale, layout.contentScale)
                    .padding(.trailing, layout.flare + 14 * layout.contentScale)
                    .frame(height: max(layout.content.minY - layout.pill.minY, 1))
                    .transition(.opacity)
            }
        }
        .frame(width: max(layout.pill.width, 1), height: max(layout.pill.height, 1), alignment: .topLeading)
        .clipShape(pillShape)
        .overlay {
            pillShape
                .stroke(Color.white.opacity(0.07 * layout.stroke), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .contentShape(pillShape)
        .onTapGesture { model.tapPill() }
        .contextMenu { IslandContextMenu(model: model, presentation: presentation) }
        .position(x: layout.pill.midX, y: layout.pill.midY)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Dynamic Ledge"))
    }

    private var contentTransition: AnyTransition {
        if nookWasOpen && presentation.homeTab != nil { return .nookTab }
        return Motion.isOpenView(presentation) ? .islandOpenContent : .islandCompactContent
    }

    private var hasBubble: Bool {
        if case .compact(_, .some) = presentation { return true }
        return false
    }

    /// The same outline the surface draws for the bubble.
    private var bubbleShape: IslandShape {
        IslandShape(topRadius: layout.topRadius, bottomRadius: layout.bottomRadius, flare: 0)
    }

    private var bubble: some View {
        ZStack {
            if case .compact(_, let secondary?) = presentation {
                MinimalView(model: model, kind: secondary, diameter: layout.bubble.height)
                    .id(secondary)
                    .transition(.bubbleContent)
            }
        }
        .frame(width: max(layout.bubble.width, 1), height: max(layout.bubble.height, 1))
        .clipShape(bubbleShape)
        .contentShape(bubbleShape)
        .onTapGesture { model.tapBubble() }
        // When tucked away the bubble is a point inside the shape; it must not steal clicks.
        .allowsHitTesting(hasBubble)
        .position(x: layout.bubble.midX, y: layout.bubble.midY)
    }
}

/// Content grows with the shape as it springs open or closed, like the Dynamic Island's: an
/// open view is drawn at its full size and scaled evenly with the shape's width from the top
/// edge, so it overshoots and settles with it. Compact content only lifts with the shape under
/// the pointer, by the same 5 %.
struct StretchWithShell: ViewModifier {
    /// The size the content is laid out for.
    let resting: CGSize
    let isOpenView: Bool
    let stretches: Bool

    /// Long enough for the resize spring to settle.
    static let resizeDuration = 0.7
    /// The smallest an open view is drawn while the shape grows out of the notch.
    nonisolated static let minimumOpenScale: CGFloat = 0.6

    func body(content: Content) -> some View {
        // The clear view takes the shape's current size, frame by frame as it animates; the
        // content keeps its own size on top of it.
        Color.clear
            .overlay(alignment: .top) { content }
            .visualEffect { [resting, isOpenView, stretches] view, proxy in
                let scale = Self.scale(current: proxy.size, resting: resting, isOpenView: isOpenView, stretches: stretches)
                return view.scaleEffect(x: scale.width, y: scale.height, anchor: .top)
            }
    }

    /// How much to scale content laid out at `resting` inside a shape that is `current` now.
    nonisolated static func scale(current: CGSize, resting: CGSize, isOpenView: Bool, stretches: Bool) -> CGSize {
        guard resting.width > 1, resting.height > 1, current.width > 0, current.height > 0 else { return CGSize(width: 1, height: 1) }
        let x = current.width / resting.width
        if isOpenView {
            guard stretches else { return CGSize(width: 1, height: 1) }
            // One scale for both directions, following the width, so the content grows and
            // bounces without being squashed. It never starts smaller than 60 %: the shape is
            // still tiny then and the content is only just fading in.
            let uniform = min(max(x, minimumOpenScale), 1.08)
            return CGSize(width: uniform, height: uniform)
        }
        // Compact: only ever grows, and only as much as the hover lift.
        let lift = min(max(x, 1), IslandMetrics.hoverScale)
        return CGSize(width: lift, height: lift)
    }
}

private struct ResizeKey: Equatable {
    let home: HomeContent
    let appearance: NotchAppearance
}

/// Identity of the content, so SwiftUI swaps views (with a transition) only when the content
/// really changes, not when a value inside it updates.
private struct ContentKey: Hashable {
    let value: String

    init(_ presentation: IslandPresentation) {
        value = switch presentation {
        case .hidden: "hidden"
        case .idle: "idle"
        case .compact(let primary, _): "compact.\(primary.rawValue)"
        case .expanded(let kind): "expanded.\(kind.rawValue)"
        case .nook(let tab): "nook.\(tab.rawValue)"
        case .alert(let alert): "alert.\(alert.kind)"
        case .drop: "drop"
        }
    }
}

struct NotchContent: View {
    let model: IslandModel
    let presentation: IslandPresentation
    let size: CGSize
    /// Width in the middle reserved for the camera.
    let cameraGap: CGFloat
    /// Home tabs: height of the strip beside the camera.
    var stripHeight: CGFloat = 0

    var body: some View {
        switch presentation {
        case .hidden, .idle:
            Color.clear
        case .compact(let primary, _):
            CompactView(model: model, kind: primary, size: size, cameraGap: cameraGap)
        case .expanded(.nowPlaying):
            NowPlayingExpandedView(model: model)
        case .expanded(.timer):
            TimerExpandedView(model: model)
        case .expanded(.stopwatch):
            StopwatchExpandedView(model: model)
        case .expanded(.call):
            CallExpandedView(model: model)
        case .expanded(.download):
            DownloadExpandedView(model: model)
        case .expanded(.stats):
            // Stats opens in the nook; this only covers the moment before that switch.
            StatsPanelBody(model: model)
        case .expanded(.aiUsage):
            // Opens in the nook too.
            AIUsagePanelBody(model: model)
        case .nook(let tab):
            NookContainer(model: model, tab: tab, cameraGap: cameraGap, stripHeight: stripHeight) {
                switch tab {
                case .home: HomeBody(model: model)
                case .tray: TrayBody(model: model)
                case .clipboard: ClipboardBody(model: model)
                case .notes: NotesBody(model: model)
                case .mirror: MirrorBody(model: model)
                case .timers: TimerPanelBody(model: model)
                case .calendar: CalendarPanelBody(model: model)
                case .reminders: RemindersPanelBody(model: model)
                case .stats: StatsPanelBody(model: model)
                case .aiUsage: AIUsagePanelBody(model: model)
                case .launcher: LauncherBody(model: model)
                }
            }
        case .alert(let alert):
            AlertView(model: model, alert: alert, cameraGap: cameraGap)
        case .drop(let targeted):
            DropView(model: model, isTargeted: targeted)
        }
    }
}

struct IslandContextMenu: View {
    let model: IslandModel
    let presentation: IslandPresentation

    var body: some View {
        if model.timer.isActive, let timer = model.timer.timer {
            Button(timer.isPaused ? "Resume Timer" : "Pause Timer") { model.timer.togglePause() }
            Button("Cancel Timer") { model.cancelTimer() }
            Divider()
        }
        if let info = model.nowPlaying.info, info.hasContent {
            Button(info.isPlaying ? "Pause" : "Play") { model.nowPlaying.togglePlayPause() }
            Button("Next Track") { model.nowPlaying.nextTrack() }
            Divider()
        }
        if model.stopwatch.isActive {
            Button(model.stopwatch.stopwatch?.isRunning == true ? "Pause Stopwatch" : "Resume Stopwatch") { model.stopwatch.togglePause() }
            Button("Reset Stopwatch") { model.resetStopwatch() }
            Divider()
        }
        if let session = model.calls.session {
            Button("Show \(session.appName)") { model.calls.showApp() }
            if model.microphone.canMute {
                Button(model.microphone.isMuted ? "Unmute Microphone" : "Mute Microphone") { model.microphone.toggle() }
            }
            Divider()
        }
        Button("Open Home") { model.showTab(.home) }
        Button("All Features") { model.showTab(.launcher) }
        Button(model.keepAwake.isOn ? "Stop Keeping Awake" : "Keep Mac Awake") { model.keepAwake.toggle() }
        Button("Settings…") { model.onOpenSettings?() }
        Button("Quit Dynamic Ledge") { NSApp.terminate(nil) }
    }
}

/// Back to Home and the activity's name, in the strip beside the camera.
private struct ActivityHeader: View {
    let model: IslandModel
    let presentation: IslandPresentation
    @Environment(\.notchScale) private var s

    var body: some View {
        // The name only when it fits beside the camera; otherwise just the back arrow.
        ViewThatFits(in: .horizontal) {
            titled(title)
            titled(shortTitle)
            BackToHomeButton(model: model)
        }
    }

    private func titled(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 3 * s) {
            BackToHomeButton(model: model)
            Text(text)
                .font(.system(size: 13 * s, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// For a narrow strip: "Mic" rather than "Microphone".
    private var shortTitle: LocalizedStringKey {
        if case .expanded(.call) = presentation, model.calls.session?.isCall == false { return "Mic" }
        return title
    }

    private var title: LocalizedStringKey {
        guard case .expanded(let kind) = presentation else { return "" }
        return switch kind {
        case .timer: (model.timer.timer?.mode ?? .plain).title
        case .stopwatch: "Stopwatch"
        case .nowPlaying: "Now Playing"
        case .call: model.calls.session?.isCall == false ? "Microphone" : "Call"
        case .download: "Downloading"
        case .stats: "Stats"
        case .aiUsage: "AI Agent Usage"
        }
    }
}
