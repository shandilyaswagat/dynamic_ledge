import AppKit
import os
import SwiftUI

/// Shows the notch on the Lock Screen while the Mac is locked, when it's switched on in
/// Settings. A separate window, created on lock and removed on unlock, so nothing of it is
/// left behind on the desktop.
@MainActor
final class LockScreenController {
    /// False when this macOS doesn't allow it; Settings then doesn't offer the switch.
    static let isAvailable = LockScreenSpace.make() != nil

    private let model: IslandModel
    private var space: LockScreenSpace?
    private var panel: NSWindow?
    private let log = Logger(subsystem: Log.subsystem, category: "lockscreen")
    private var observers: [NSObjectProtocol] = []
    private var isLocked = false

    init(model: IslandModel) {
        self.model = model
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locked(true) }
        })
        observers.append(center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.locked(false) }
        })
        observeSetting()
    }

    func tearDown() {
        observers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        observers.removeAll()
        hide()
        space?.tearDown()
    }

    #if DEBUG
    /// Debug builds: show the Lock Screen panel without locking, to check how it looks.
    func preview(_ on: Bool) {
        isLocked = on
        if on { show() } else { hide() }
    }
    #endif

    private func locked(_ locked: Bool) {
        log.notice("Screen \(locked ? "locked" : "unlocked", privacy: .public); show on Lock Screen: \(self.model.settings.lockScreenEnabled, privacy: .public)")
        isLocked = locked
        update()
    }

    private func update() {
        if isLocked, model.settings.lockScreenEnabled {
            show()
        } else {
            hide()
        }
    }

    private func observeSetting() {
        withObservationTracking {
            _ = model.settings.lockScreenEnabled
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.update()
                self?.observeSetting()
            }
        }
    }

    private func show() {
        guard panel == nil, let screen = Self.screen() else { return }
        if space == nil { space = LockScreenSpace.make() }
        guard let space else {
            log.error("Lock Screen space unavailable")
            return
        }
        // The same window size and placement as the notch's own, so everything lines up.
        let metrics = ScreenMetrics(screen: screen)
        let size = model.engine(for: metrics).windowSize
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        let panel = LockScreenWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.contentView = NSHostingView(rootView: LockScreenView(model: model, metrics: metrics))
        panel.setFrame(frame, display: true)
        // Into the Lock Screen's space first, then on screen.
        let placed = space.place(panel)
        panel.orderFrontRegardless()
        self.panel = panel
        log.notice("Lock Screen panel shown (placed: \(placed, privacy: .public))")
    }

    private func hide() {
        guard let panel else { return }
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
        log.notice("Lock Screen panel removed")
    }

    /// The MacBook's screen, where the notch is, or else the main one.
    private static func screen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }
}

/// A borderless window macOS lets appear before you unlock, above everything else.
private final class LockScreenWindow: NSWindow {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        // Just for looking at, like the notch at rest: clicks go to the Lock Screen.
        ignoresMouseEvents = true
        canBecomeVisibleWithoutLogin = true
        level = NSWindow.Level(rawValue: Int(Int32.max - 2))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
}
