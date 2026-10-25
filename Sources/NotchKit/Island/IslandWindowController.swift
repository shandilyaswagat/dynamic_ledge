import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Which display a window is on, for the views inside it.
@MainActor
@Observable
final class DisplayContext {
    var id: UInt32 = 0
    var metrics: ScreenMetrics = .sample
}

/// Places the island panel on a display and routes the pointer to the model. Normally there is
/// one; with "All displays" there is one per screen, and only the screen you're using (the
/// model's active display) handles the pointer, drags and keyboard. The others mirror it.
@MainActor
public final class IslandWindowController {
    private let model: IslandModel
    /// Set for one window per screen ("All displays"); nil for the single window that picks its
    /// screen from the Display setting.
    private let fixedDisplayID: UInt32?
    private let context = DisplayContext()
    private let panel = IslandPanel()
    private let hostingView: IslandHostingView<IslandRootView>
    private var screen: NSScreen?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []

    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var isFileDragging = false
    private var documentWindowDrag = DocumentWindowDrag()
    private var documentDragTask: Task<Void, Never>?
    private var documentGestureStart: CGPoint?
    private var dragActivationTask: Task<Void, Never>?
    private var nativeDragTask: Task<Void, Never>?
    private var lastIdleDragChangeCount = NSPasteboard(name: .drag).changeCount
    private var scrollTotal: CGSize = .zero
    private var scrollHandled = false
    private var lastWheelStep = Date.distantPast
    private var workspaceObservers: [NSObjectProtocol] = []

    public init(model: IslandModel, displayID: UInt32? = nil) {
        self.model = model
        fixedDisplayID = displayID
        hostingView = IslandHostingView(rootView: IslandRootView(model: model, display: context))
        // The window size is ours to set; SwiftUI must never resize it to fit its content.
        hostingView.sizingOptions = []
        hostingView.onMouseMoved = { [weak self] in self?.pointerChanged() }
        hostingView.onDraggingEntered = { [weak self] sender in
            self?.updateNativeDrag(sender) ?? []
        }
        hostingView.onDraggingUpdated = { [weak self] sender in
            self?.updateNativeDrag(sender) ?? []
        }
        hostingView.onDraggingExited = { [weak self] in self?.endNativeDrag() }
        hostingView.onPerformDrag = { [weak self] sender in
            guard let self else { return false }
            let urls = FileDropReader.urls(from: sender.draggingPasteboard)
            let destination = self.dropDestination(at: self.windowPoint())
            self.endNativeDrag()
            guard let destination else { return false }
            return self.model.acceptDrop(urls, into: destination)
        }
        panel.contentView = hostingView
        updateScreen()
        installMonitors()
        watchDragActivation()
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
        dragActivationTask?.cancel()
        dragActivationTask = nil
        nativeDragTask?.cancel()
        nativeDragTask = nil
        cancelDocumentDrag()
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        panel.orderOut(nil)
    }

    // MARK: Placement

    private var isActive: Bool { model.activeDisplayID == context.id }

    /// Makes this window's screen the one in use when the pointer comes near it.
    private func activateIfPointerHere() -> Bool {
        guard panel.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) else { return false }
        return model.activate(display: context.id, metrics: context.metrics)
    }

    private func chooseScreen() -> NSScreen? {
        if let fixedDisplayID {
            return NSScreen.screens.first { Self.displayID($0) == fixedDisplayID }
        }
        switch model.settings.display {
        case .specific(let uuid):
            return NSScreen.screens.first { Self.uuid($0) == uuid } ?? Self.builtIn
        case .automatic, .all:
            return Self.builtIn
        case .followPointer:
            let pointer = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
                ?? NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
                ?? NSScreen.screens.first
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
        let id = Self.displayID(chosen)
        if context.id != id { context.id = id }
        if context.metrics != metrics { context.metrics = metrics }
        if fixedDisplayID == nil {
            model.useOnly(display: id, metrics: metrics)
        } else if isActive {
            model.activate(display: id, metrics: metrics)
        }
        reposition()
        panel.orderFrontRegardless()
    }

    /// NSScreen objects are recreated freely; the display ID identifies the physical display.
    static func displayID(_ screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// Survives reconnecting and restarting, unlike the display ID.
    static func uuid(_ screen: NSScreen) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID(screen))?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    static var builtIn: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    private func reposition() {
        guard let screen else { return }
        let engine = model.engine(for: context.metrics)
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
            _ = model.engine(for: context.metrics)
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
        let wantsKeyboard = isActive && model.presentation == .notes
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
            _ = isActive && model.presentation == .notes
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
        guard model.settings.display == .followPointer, !isFileDragging, documentDragTask == nil,
              !model.presentation.isExpandedFamily, let current = screen else { return }
        let pointer = NSEvent.mouseLocation
        guard !NSMouseInRect(pointer, current.frame, false),
              NSScreen.screens.contains(where: { NSMouseInRect(pointer, $0.frame, false) }) else { return }
        updateScreen()
    }

    private func pointerChanged() {
        followPointerIfNeeded()
        // Another screen is in use: this window just mirrors it, unless the pointer arrives here.
        guard isActive || activateIfPointerHere() else {
            if !panel.ignoresMouseEvents { panel.ignoresMouseEvents = true }
            return
        }
        // Most pointer movement happens far from the notch. Skip the layout work there unless
        // something still needs to be switched off.
        let location = NSEvent.mouseLocation
        let nearWindow = panel.frame.insetBy(dx: -8, dy: -8).contains(location)
        // A pending reveal still needs to hear that the pointer left, however fast it went.
        if !nearWindow, !isFileDragging, !model.isDocumentWindowDrag, panel.ignoresMouseEvents, !model.isHoveringPill,
           !model.isHoveringNotch, !model.isRevealPending {
            return
        }
        let wantsMouse = model.pointerMoved(to: windowPoint())
        // A window move is owned by the source app, not an NSDraggingSession. Keep its mouse
        // events passing through the overlay until release; the global monitor/poller handles it.
        if model.isDocumentWindowDrag {
            panel.ignoresMouseEvents = true
            return
        }
        let shouldAcceptMouse = wantsMouse || isFileDragging || model.isFileDragNear || model.isDocumentWindowDrag
        if panel.ignoresMouseEvents == shouldAcceptMouse {
            panel.ignoresMouseEvents = !shouldAcceptMouse
        }
    }

    private func handle(_ event: NSEvent, isLocal: Bool) {
        guard isActive || activateIfPointerHere() else { return }
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if event.type == .leftMouseDown {
                dragChangeCount = NSPasteboard(name: .drag).changeCount
                cancelDocumentDrag()
                if model.settings.trayEnabled, (!isLocal || event.window !== panel) {
                    documentGestureStart = NSEvent.mouseLocation
                    _ = documentWindowDrag.begin(at: NSEvent.mouseLocation)
                    watchDocumentDrag()
                }
            }
            // Clicks in other apps, and in our own Settings window, are outside the notch.
            if !isLocal || event.window !== panel {
                model.outsideClick()
            }
        case .leftMouseDragged:
            updateFileDrag()
        case .leftMouseUp:
            finishDocumentDrag()
            // AppKit completes a native drop after delivering mouse-up. Its destination
            // callbacks (or the delayed release fallback) clear that session.

        default:
            break
        }
        pointerChanged()
    }

    private func dropDestination(at point: CGPoint) -> IslandModel.DropZone? {
        DropPolicy.destination(at: point, content: model.layout.content,
            tray: model.settings.trayEnabled,
            airDrop: model.settings.airDropEnabled && !model.isDocumentWindowDrag)
    }

    private func updateNativeDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isActive || activateIfPointerHere() else { return [] }
        let urls = FileDropReader.urls(from: sender.draggingPasteboard)
        guard model.acceptsFileDrops, !model.isDraggingFromTray, !urls.isEmpty else { return [] }
        cancelDocumentDrag()
        if !isFileDragging { isFileDragging = true; watchForDragEnd() }
        model.fileDragChanged(isDragging: true, at: windowPoint())
        let destination = dropDestination(at: windowPoint())
        model.setTargeted(destination, destination != nil)
        pointerChanged()
        if destination == .airDrop, !urls.contains(where: \.isFileURL) { return [] }
        return destination == nil ? [] : .copy
    }

    private func endNativeDrag() {
        nativeDragTask?.cancel()
        nativeDragTask = nil
        isFileDragging = false
        guard isActive else { return }
        model.fileDragChanged(isDragging: false, at: nil)
        model.setTargeted(nil, false)
        pointerChanged()
    }

    private func updateFileDrag() {
        guard isActive else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCount,
              !FileDropReader.urls(from: pasteboard).isEmpty, !model.isDraggingFromTray else { return }
        cancelDocumentDrag()
        if !isFileDragging { isFileDragging = true; watchForDragEnd() }
        model.fileDragChanged(isDragging: true, at: windowPoint())
    }

    /// Some source applications consume mouse-drag events in a tracking loop. Detect their
    /// pasteboard/held-button state independently, without relying on a global drag callback.
    private func watchDragActivation() {
        dragActivationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }
                guard self.isActive else { continue }
                let pasteboard = NSPasteboard(name: .drag)
                guard NSEvent.pressedMouseButtons & 1 != 0 else {
                    self.lastIdleDragChangeCount = pasteboard.changeCount
                    continue
                }
                guard self.model.acceptsFileDrops, !self.model.isDraggingFromTray else { continue }
                if !self.isFileDragging, self.documentGestureStart == nil,
                   NSWorkspace.shared.frontmostApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    self.dragChangeCount = self.lastIdleDragChangeCount
                    if self.model.settings.trayEnabled {
                        self.documentGestureStart = NSEvent.mouseLocation
                        _ = self.documentWindowDrag.begin(at: NSEvent.mouseLocation)
                        self.watchDocumentDrag()
                    }
                }
                self.updateFileDrag()
                if self.isFileDragging {
                    self.model.fileDragChanged(isDragging: true, at: self.windowPoint())
                    self.pointerChanged()
                }
            }
        }
    }

    private func watchDocumentDrag() {
        documentDragTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                guard self.isActive else { self.cancelDocumentDrag(); return }
                if NSEvent.pressedMouseButtons & 1 == 0 { self.finishDocumentDrag(); return }
                guard self.model.settings.trayEnabled, !self.isFileDragging else { self.cancelDocumentDrag(); return }
                let missingAccess = !DocumentWindowDrag.hasAccess
                let pointerMoved = self.documentGestureStart.map {
                    DocumentDragPolicy.hasMoved(from: $0, to: NSEvent.mouseLocation)
                } == true
                let moved = self.documentWindowDrag.hasMoved || (missingAccess && pointerMoved)
                self.model.isDocumentWindowDrag = moved
                self.model.fileDragChanged(isDragging: moved, at: self.windowPoint())
                let destination: IslandModel.DropZone? = moved && self.documentDropRegion.contains(self.windowPoint()) ? .tray : nil
                self.model.setTargeted(destination, destination != nil)
                self.pointerChanged()
            }
        }
    }

    private var documentDropRegion: CGRect {
        DocumentDragPolicy.dropRegion(activation: model.engine.dropZone, pill: model.layout.pill)
    }

    private func finishDocumentDrag() {
        guard documentDragTask != nil else { return }
        let overTarget = documentDropRegion.contains(windowPoint())
        let missingAccess = !DocumentWindowDrag.hasAccess && overTarget
            && documentGestureStart.map { DocumentDragPolicy.hasMoved(from: $0, to: NSEvent.mouseLocation) } == true
        let shouldStore = documentWindowDrag.hasMoved && overTarget
        documentGestureStart = nil
        documentDragTask?.cancel()
        documentDragTask = nil
        model.isDocumentWindowDrag = false
        model.fileDragChanged(isDragging: false, at: nil)
        model.setTargeted(nil, false)
        guard shouldStore else {
            documentWindowDrag.reset()
            if missingAccess {
                model.showDropFailure("Accessibility access is required to read the document in a moved window.")
                DocumentWindowDrag.requestAccess()
            }
            pointerChanged()
            return
        }
        // Retain the captured session while asynchronous resolution completes.
        let session = documentWindowDrag
        documentWindowDrag = DocumentWindowDrag()
        Task { @MainActor [weak self] in
            let result = await session.resolve()
            guard let self, self.model.settings.trayEnabled else { return }
            if let url = result.url { _ = self.model.acceptDrop([url], into: .tray) }
            else if let message = result.message { self.model.showDropFailure(message) }
        }
        pointerChanged()
    }

    private func cancelDocumentDrag() {
        documentDragTask?.cancel()
        documentDragTask = nil
        documentGestureStart = nil
        documentWindowDrag.reset()
        // The drag state belongs to the screen in use; a mirroring window leaves it alone.
        if isActive, model.isDocumentWindowDrag {
            model.isDocumentWindowDrag = false
            model.fileDragChanged(isDragging: false, at: nil)
            model.setTargeted(nil, false)
        }
    }

    private func watchForDragEnd() {
        guard nativeDragTask == nil else { return }
        nativeDragTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    if NSEvent.pressedMouseButtons & 1 == 0 { self.endNativeDrag(); return }
                }
            }
        }
    }

    /// Two-finger gestures over the notch, one action per gesture:
    /// sideways skips songs when music is in front (otherwise swaps activities), pulling down
    /// opens the notch and pushing up closes it. Home and its tabs keep their own scrolling.
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard isActive else { return false }
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
