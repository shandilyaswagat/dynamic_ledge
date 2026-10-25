import AppKit
import SwiftUI

/// Toolbar-style settings window, like Safari's.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public enum Tab: Int, CaseIterable {
        case general
        case appearance
        case activities
        case home
        case about
    }

    private let model: IslandModel
    private var window: NSWindow?
    private var tabController: SettingsTabViewController?

    public init(model: IslandModel) {
        self.model = model
    }

    public func show(_ tab: Tab? = nil) {
        let window = window ?? makeWindow()
        if let tab {
            tabController?.selectedTabViewItemIndex = tab.rawValue
        }
        if !window.isVisible {
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        updatePreview()
    }

    public func windowWillClose(_ notification: Notification) {
        model.isPreviewing = false
    }

    private func updatePreview() {
        let showingAppearance = window?.isVisible == true && tabController?.selectedTabViewItemIndex == Tab.appearance.rawValue
        if model.isPreviewing != showingAppearance {
            model.isPreviewing = showingAppearance
        }
    }

    private func makeWindow() -> NSWindow {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        tabs.onSelect = { [weak self] in self?.updatePreview() }

        let settings = model.settings
        tabs.addTabViewItem(item("General", symbol: "gearshape", size: CGSize(width: 520, height: 552), GeneralSettingsView(settings: settings)))
        tabs.addTabViewItem(item("Appearance", symbol: "capsule", size: CGSize(width: 520, height: 500), AppearanceSettingsView(settings: settings)))
        tabs.addTabViewItem(item("Activities", symbol: "square.stack.3d.up", size: CGSize(width: 520, height: 580), ActivitiesSettingsView(settings: settings, nowPlaying: model.nowPlaying)))
        tabs.addTabViewItem(item("Home", symbol: "house", size: CGSize(width: 520, height: 600), HomeSettingsView(settings: settings, calendar: model.calendar, shortcuts: model.shortcuts)))
        tabs.addTabViewItem(item("About", symbol: "info.circle", size: CGSize(width: 520, height: 380), AboutSettingsView(settings: model.settings, updater: model.updater)))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(tabs.tabViewItems.first?.viewController?.preferredContentSize ?? CGSize(width: 520, height: 552))
        window.title = tabs.tabViewItems.first?.label ?? ""
        window.setFrameAutosaveName("DynamicNotchSettings")
        self.window = window
        tabController = tabs
        return window
    }

    private func item<Content: View>(_ title: String, symbol: String, size: CGSize, _ content: Content) -> NSTabViewItem {
        let host = NSHostingController(rootView: content.frame(width: size.width, height: size.height))
        host.preferredContentSize = size
        host.title = title
        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}

/// Resizes the window to each tab's size, keeping the top edge still.
final class SettingsTabViewController: NSTabViewController {
    var onSelect: (() -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let size = tabViewItem?.viewController?.preferredContentSize, let window = view.window, size != .zero {
            let target = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
            var frame = window.frame
            frame.origin.y += frame.height - target.height
            frame.size = target.size
            window.setFrame(frame, display: true, animate: window.isVisible)
        }
        view.window?.title = tabViewItem?.label ?? ""
        onSelect?()
    }
}
