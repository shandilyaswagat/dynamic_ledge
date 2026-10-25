import AppKit
import SwiftUI

/// Borderless panel above the menu bar. It never activates the app, and only takes the keyboard
/// while Notes is open.
final class IslandPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        setAccessibilityLabel("Dynamic Notch")
    }

    /// True while a view in the panel needs typing (Notes).
    var acceptsKeyboard = false

    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }

    // The panel sits over the menu bar on purpose.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Hosting view that reacts to the first click even though the app is in the background.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var onMouseMoved: (() -> Void)?
    var onDraggingEntered: ((NSDraggingInfo) -> NSDragOperation)?
    var onDraggingUpdated: ((NSDraggingInfo) -> NSDragOperation)?
    var onDraggingExited: (() -> Void)?
    var onPerformDrag: ((NSDraggingInfo) -> Bool)?
    private var trackingArea: NSTrackingArea?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([
            .fileURL,
            .URL,
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDraggingEntered?(sender) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDraggingUpdated?(sender) ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDraggingExited?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return onPerformDrag?(sender) ?? false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onMouseMoved?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseMoved?()
    }
}

extension ScreenMetrics {
    @MainActor
    init(screen: NSScreen) {
        let frame = screen.frame
        var notch: CGRect?
        if screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let minX = left.maxX - frame.minX
            let maxX = right.minX - frame.minX
            if maxX > minX {
                notch = CGRect(x: minX, y: 0, width: maxX - minX, height: screen.safeAreaInsets.top)
            }
        }
        let reservedTop = frame.maxY - screen.visibleFrame.maxY
        let menuBar = reservedTop > 0 ? reservedTop : NSStatusBar.system.thickness + 2
        self.init(size: frame.size, notch: notch, menuBarHeight: menuBar)
    }
}
