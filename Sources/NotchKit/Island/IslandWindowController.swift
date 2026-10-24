import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Places the island panel on the right display and routes the pointer to the model.
@MainActor
public final class IslandWindowController {
    /// Finder uses `public.file-url`; document proxy icons, including Pages, can expose the
    /// broader `public.url` representation instead. The receiver validates that it is a local
    /// file before accepting the drop.
    private static let supportedFileDragTypes: Set<NSPasteboard.PasteboardType> = [
        .fileURL,
        NSPasteboard.PasteboardType(UTType.url.identifier),
    ]

    private let model: IslandModel
    private let panel = IslandPanel()
    private let hostingView: IslandHostingView<IslandRootView>
    private var screen: NSScreen?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var isFileDragging = false
    private var scrollTotal: CGSize = .zero
    private var scrollHandled = false
    private var lastWheelStep = Date.distantPast
    private var workspaceObservers: [NSObjectProtocol] = []

    public init(model: IslandModel) {
        self.model = model
        hostingView = IslandHostingView(rootView: IslandRootView(model: model))
        // The window size is ours to set; SwiftUI must never resize it to fit its content.
        hostingView.sizingOptions = []
        hostingView.onMouseMoved = { [weak self] in self?.pointerChanged() }
        panel.contentView = hostingView
        updateScreen()
        installMonitors()
        observeEnvironment()
        observeLayout()
        observeKeyboard()
        panel.orderFrontRegardless()
        #if DEBUG
        // QA: re-read the real pointer position, as a mouse move would.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("DynamicNotch.debug.pointer"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerChanged() }
        })
        #endif
    }

    public func tearDown() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        panel.orderOut(nil)
    }

    // MARK: Placement

    private func chooseScreen() -> NSScreen? {
        switch model.settings.display {
        case .followPointer:
            let pointer = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
                ?? NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
                ?? NSScreen.screens.first
        case .automatic:
            return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
        case .main:
            return NSScreen.screens.first
        }
    }

    private func updateScreen() {
        guard let chosen = chooseScreen() else {
            panel.orderOut(nil)
            return
        }
        screen = chosen
        let metrics = ScreenMetrics(screen: chosen)
        if model.screen != metrics {
            model.screen = metrics
        }
        reposition()
        panel.orderFrontRegardless()
    }

    /// NSScreen objects are recreated freely; the display ID identifies the physical display.
    private static func displayID(_ screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private func reposition() {
        guard let screen else { return }
        let engine = model.engine
        let size = engine.windowSize
        let frame = NSRect(
            x: screen.frame.minX + engine.windowOriginX,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        ).integral
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    private func observeLayout() {
        withObservationTracking {
            _ = model.engine
            _ = model.settings.display
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wanted = self.chooseScreen()
                if wanted.map(Self.displayID) != self.screen.map(Self.displayID) {
                    self.updateScreen()
                } else {
                    self.reposition()
                }
                self.observeLayout()
            }
        }
    }

    /// Notes takes the keyboard while it's open and hands it straight back when it closes.
    /// The panel never activates the app, so the app you were in stays in front.
    private func observeKeyboard() {
        let wantsKeyboard = model.presentation == .notes
        if wantsKeyboard {
            panel.acceptsKeyboard = true
            panel.makeKey()
        } else {
            if panel.isKeyWindow {
                panel.resignKey()
            }
            panel.acceptsKeyboard = false
        }
        withObservationTracking {
            _ = model.presentation == .notes
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.observeKeyboard() }
        }
    }

    private func observeEnvironment() {
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateScreen() }
        })
        // Spaces and full-screen changes can reorder windows; keep the panel on top.
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.orderFrontRegardless() }
        })
    }

    // MARK: Pointer

    private func installMonitors() {
        let pointerEvents: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseUp,
        ]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: pointerEvents, handler: { [weak self] event in
            // AppKit calls monitors on the main thread.
            nonisolated(unsafe) let event = event
            MainActor.assumeIsolated { self?.handle(event, isLocal: false) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: pointerEvents.union(.scrollWheel), handler: { [weak self] event in
            nonisolated(unsafe) let event = event
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                if event.type == .scrollWheel {
                    return self.handleScroll(event)
                }
                self.handle(event, isLocal: true)
                return false
            }
            return consumed ? nil : event
        }) {
            monitors.append(local)
        }
    }

    private func windowPoint() -> CGPoint {
        let location = NSEvent.mouseLocation
        return CGPoint(x: location.x - panel.frame.minX, y: panel.frame.maxY - location.y)
    }

    /// With "follow the pointer", hop to the display the pointer moved to, but never while
    /// something is open or being dragged, so nothing jumps away from under the user.
    private func followPointerIfNeeded() {
        guard model.settings.display == .followPointer, !isFileDragging,
              !model.presentation.isExpandedFamily, let current = screen else { return }
        let pointer = NSEvent.mouseLocation
        guard !NSMouseInRect(pointer, current.frame, false),
              NSScreen.screens.contains(where: { NSMouseInRect(pointer, $0.frame, false) }) else { return }
        updateScreen()
    }

    private func pointerChanged() {
        followPointerIfNeeded()
        // Most pointer movement happens far from the notch. Skip the layout work there unless
        // something still needs to be switched off.
        let location = NSEvent.mouseLocation
        let nearWindow = panel.frame.insetBy(dx: -8, dy: -8).contains(location)
        if !nearWindow, !isFileDragging, panel.ignoresMouseEvents, !model.isHoveringPill, !model.isHoveringNotch {
            return
        }
        let wantsMouse = model.pointerMoved(to: windowPoint())
        if panel.ignoresMouseEvents == wantsMouse {
            panel.ignoresMouseEvents = !wantsMouse
        }
    }

    private func handle(_ event: NSEvent, isLocal: Bool) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if event.type == .leftMouseDown {
                dragChangeCount = NSPasteboard(name: .drag).changeCount
            }
            // Clicks in other apps, and in our own Settings window, are outside the notch.
            if !isLocal || event.window !== panel {
                model.outsideClick()
            }
        case .leftMouseDragged:
            updateFileDrag()
        case .leftMouseUp:
            if isFileDragging {
                isFileDragging = false
                model.fileDragChanged(isDragging: false, at: nil)
            }
        default:
            break
        }
        pointerChanged()
    }

    /// A file drag is a mouse drag whose drag pasteboard changed since the mouse went down.
    private func updateFileDrag() {
        let pasteboard = NSPasteboard(name: .drag)
        if !isFileDragging,
           pasteboard.changeCount != dragChangeCount,
           let types = pasteboard.types,
           !Self.supportedFileDragTypes.isDisjoint(with: types) {
            isFileDragging = true
            watchForDragEnd()
        }
        if isFileDragging {
            model.fileDragChanged(isDragging: true, at: windowPoint())
        }
    }

    /// Drops onto other apps don't always send us a mouse-up, so also watch the button state.
    private func watchForDragEnd() {
        Task { @MainActor [weak self] in
            while let self, self.isFileDragging {
                try? await Task.sleep(for: .milliseconds(250))
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    self.isFileDragging = false
                    self.model.fileDragChanged(isDragging: false, at: nil)
                    self.pointerChanged()
                }
            }
        }
    }

    /// Two-finger gestures over the notch, one action per gesture:
    /// sideways skips songs when music is in front (otherwise swaps activities), pulling down
    /// opens the notch and pushing up closes it. Home and its tabs keep their own scrolling.
    private func handleScroll(_ event: NSEvent) -> Bool {
        let presentation = model.presentation
        guard model.isHoveringPill || model.isHoveringNotch else { return false }
        let accepts: Bool = switch presentation {
        case .hidden, .idle, .compact, .expanded: true
        default: false
        }
        guard accepts else { return false }
        // Momentum after a swipe belongs to the swipe that was already handled.
        if event.momentumPhase != [] {
            return true
        }
        let isTrackpadGesture = event.phase != []
        if isTrackpadGesture, event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            scrollTotal = .zero
            scrollHandled = false
        }
        if isTrackpadGesture {
            scrollTotal.width += event.scrollingDeltaX
            scrollTotal.height += event.scrollingDeltaY
            guard !scrollHandled else { return true }
            if abs(scrollTotal.width) > 30, abs(scrollTotal.width) > abs(scrollTotal.height) {
                scrollHandled = true
                model.swipe(forward: scrollTotal.width < 0)
            } else if abs(scrollTotal.height) > 24, abs(scrollTotal.height) > abs(scrollTotal.width) {
                scrollHandled = true
                model.pull(open: Self.fingersMovedDown(scrollTotal.height, event))
            }
        } else if Date().timeIntervalSince(lastWheelStep) > 0.4 {
            // A mouse wheel has no phases: one step per notch, with a short cooldown.
            lastWheelStep = Date()
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
                model.swipe(forward: event.scrollingDeltaX < 0)
            } else if event.scrollingDeltaY != 0 {
                model.pull(open: Self.fingersMovedDown(event.scrollingDeltaY, event))
            }
        }
        return true
    }

    /// Scroll deltas follow the fingers with natural scrolling and are reversed without it.
    private static func fingersMovedDown(_ deltaY: CGFloat, _ event: NSEvent) -> Bool {
        event.isDirectionInvertedFromDevice ? deltaY > 0 : deltaY < 0
    }
}
