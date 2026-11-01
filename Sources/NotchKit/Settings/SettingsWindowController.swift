import AppKit
import SwiftUI
import Observation

@MainActor
@Observable
final class SettingsNavigation {
    struct Entry: Equatable {
        var selection: SettingsWindowController.Tab
        var generalPage: GeneralPage
    }

    private var history: [Entry] = [Entry(selection: .general, generalPage: .overview)]
    private var historyIndex: Int = 0

    var current: Entry {
        history[historyIndex]
    }

    var selection: SettingsWindowController.Tab {
        get { current.selection }
        set { navigateTo(selection: newValue, generalPage: .overview) }
    }

    var generalPage: GeneralPage {
        get { current.generalPage }
        set { navigateTo(selection: .general, generalPage: newValue) }
    }

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }

    func navigateTo(selection: SettingsWindowController.Tab, generalPage: GeneralPage) {
        let entry = Entry(selection: selection, generalPage: generalPage)
        guard entry != current else { return }
        if historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        history.append(entry)
        historyIndex = history.count - 1
    }

    func goBack() {
        guard canGoBack else { return }
        historyIndex -= 1
    }

    func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
    }
}

enum GeneralPage {
    case overview, about, softwareUpdate, nowPlaying, codingAssistants
}

/// A sidebar keeps the app's settings grouped by purpose.
@MainActor
public final class SettingsWindowController: NSObject, NSWindowDelegate {
    public enum Tab: Int, CaseIterable, Hashable, Identifiable {
        case general, appearance, activities, home, about, nowPlaying, codingAssistants, shortcuts, softwareUpdate
        public var id: Int { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .appearance: "Appearance"
            case .activities: "Activities & Alerts"
            case .home: "Home & Widgets"
            case .about: "About"
            case .nowPlaying: "Now Playing"
            case .codingAssistants: "Coding Assistants"
            case .shortcuts: "Shortcuts"
            case .softwareUpdate: "Software Update"
            }
        }

        /// The sidebar keeps the icons the Settings tabs have always had.
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .appearance: "capsule"
            case .activities: "square.stack.3d.up"
            case .home: "house"
            case .about: "info.circle"
            case .nowPlaying: "music.note"
            case .codingAssistants: "terminal"
            case .shortcuts: "square.2.layers.3d"
            case .softwareUpdate: "arrow.down.circle"
            }
        }
    }

    private let model: IslandModel
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    public init(model: IslandModel) { self.model = model }

    public func show(_ tab: Tab? = nil) {
        if let tab {
            switch tab {
            case .about:
                navigation.navigateTo(selection: .general, generalPage: .about)
            case .nowPlaying:
                navigation.navigateTo(selection: .general, generalPage: .nowPlaying)
            case .codingAssistants:
                navigation.navigateTo(selection: .general, generalPage: .codingAssistants)
            case .shortcuts:
                navigation.navigateTo(selection: .home, generalPage: .overview)
            case .softwareUpdate:
                if model.updater.availableRelease != nil {
                    navigation.navigateTo(selection: .softwareUpdate, generalPage: .overview)
                } else {
                    navigation.navigateTo(selection: .general, generalPage: .softwareUpdate)
                }
            default:
                navigation.navigateTo(selection: tab, generalPage: .overview)
            }
        }
        let window = window ?? makeWindow()
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        updatePreview()
    }

    public func windowWillClose(_ notification: Notification) { model.isPreviewing = false }

    private func updatePreview() {
        model.isPreviewing = window?.isVisible == true && navigation.selection == .appearance
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsRootView(
            model: model,
            navigation: navigation,
            selectionChanged: { [weak self] in self?.updatePreview() },
            // The page title shows in the toolbar, as in System Settings. The first one arrives
            // while the window is still being made, so it's applied on the next turn.
            titleChanged: { [weak self] title in DispatchQueue.main.async { self?.window?.title = title } }
        )
        let host = NSHostingController(rootView: root)
        // Lets SwiftUI put the back and forward buttons in the toolbar; the title is set below.
        host.sceneBridgingOptions = [.toolbars]
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        window.setContentSize(NSSize(width: 800, height: 620))
        window.minSize = NSSize(width: 700, height: 480)
        window.setFrameAutosaveName("DynamicNotchSettingsSidebar")
        self.window = window
        return window
    }
}

private struct SettingsRootView: View {
    let model: IslandModel
    @Bindable var navigation: SettingsNavigation
    let selectionChanged: () -> Void
    let titleChanged: (String) -> Void
    @State private var search = ""

    private var isUpdateAvailable: Bool {
        model.updater.availableRelease != nil
    }

    private var categories: [SettingsWindowController.Tab] {
        var all: [SettingsWindowController.Tab] = [
            .general,
            .appearance,
            .home,
            .activities
        ]
        if isUpdateAvailable {
            all.insert(.softwareUpdate, at: 0)
        }
        return all
    }

    private var searchResults: [SettingsSearchResult] { SettingsSearch.results(for: search) }
    private var isSearching: Bool { !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func open(_ result: SettingsSearchResult) {
        switch result.page {
        case .general: navigation.navigateTo(selection: .general, generalPage: .overview)
        case .about: navigation.navigateTo(selection: .general, generalPage: .about)
        case .update: navigation.navigateTo(selection: .general, generalPage: .softwareUpdate)
        case .media: navigation.navigateTo(selection: .general, generalPage: .nowPlaying)
        case .coding: navigation.navigateTo(selection: .general, generalPage: .codingAssistants)
        case .appearance: navigation.navigateTo(selection: .appearance, generalPage: .overview)
        case .home: navigation.navigateTo(selection: .home, generalPage: .overview)
        case .activities: navigation.navigateTo(selection: .activities, generalPage: .overview)
        }
        search = ""
    }

    var body: some View {
        NavigationSplitView {
            Group {
                if isSearching {
                    if searchResults.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        List(searchResults) { result in
                            Button { open(result) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.title)
                                    Text(result.path).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .listStyle(.sidebar)
                    }
                } else {
                    List(categories, selection: Binding<SettingsWindowController.Tab?>(get: { navigation.selection }, set: { selection in
                        if let selection { navigation.navigateTo(selection: selection, generalPage: .overview) }
                    })) { tab in
                        Label(tab.title, systemImage: tab.symbol)
                            .badge(tab == .softwareUpdate && isUpdateAvailable ? 1 : 0)
                            .tag(tab)
                    }
                    .listStyle(.sidebar)
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Search")
            .onSubmit(of: .search) { if let first = searchResults.first { open(first) } }
            .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 260)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch navigation.selection {
                    case .general:
                        switch navigation.generalPage {
                        case .overview:
                            GeneralSettingsView(
                                settings: model.settings,
                                updater: model.updater,
                                openAbout: { navigation.generalPage = .about },
                                openSoftwareUpdate: { navigation.generalPage = .softwareUpdate },
                                openNowPlaying: { navigation.generalPage = .nowPlaying },
                                openCodingAssistants: { navigation.generalPage = .codingAssistants }
                            )
                        case .about:
                            AboutSettingsView()
                        case .softwareUpdate:
                            SoftwareUpdateSettingsView(settings: model.settings, updater: model.updater)
                        case .nowPlaying:
                            NowPlayingSettingsView(settings: model.settings, nowPlaying: model.nowPlaying)
                        case .codingAssistants:
                            CodingAssistantSettingsView(settings: model.settings, aiUsage: model.aiUsage)
                        }
                    case .softwareUpdate: SoftwareUpdateSettingsView(settings: model.settings, updater: model.updater)
                    case .appearance: AppearanceSettingsView(settings: model.settings)
                    case .activities: ActivitiesSettingsView(settings: model.settings)
                    case .home: HomeSettingsView(settings: model.settings, calendar: model.calendar, shortcuts: model.shortcuts)
                    case .nowPlaying: NowPlayingSettingsView(settings: model.settings, nowPlaying: model.nowPlaying)
                    case .codingAssistants: CodingAssistantSettingsView(settings: model.settings, aiUsage: model.aiUsage)
                    case .shortcuts: ShortcutsSettingsView(settings: model.settings, shortcuts: model.shortcuts)
                    case .about: AboutSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button { navigation.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!navigation.canGoBack)
                        .keyboardShortcut("[", modifiers: .command)
                        .help("Back")
                    Button { navigation.goForward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!navigation.canGoForward)
                        .keyboardShortcut("]", modifiers: .command)
                        .help("Forward")
                }
            }
        }
        .onChange(of: navigation.selection) { _, _ in selectionChanged() }
        .onChange(of: detailTitle, initial: true) { _, title in titleChanged(title) }
    }

    private var isAbout: Bool {
        navigation.selection == .about || (navigation.selection == .general && navigation.generalPage == .about)
    }

    private var isSoftwareUpdate: Bool {
        navigation.selection == .softwareUpdate || (navigation.selection == .general && navigation.generalPage == .softwareUpdate)
    }

    private var isNowPlaying: Bool {
        navigation.selection == .nowPlaying || (navigation.selection == .general && navigation.generalPage == .nowPlaying)
    }

    private var isCodingAssistants: Bool {
        navigation.selection == .codingAssistants || (navigation.selection == .general && navigation.generalPage == .codingAssistants)
    }

    private var detailTitle: String {
        if isAbout { return "About" }
        if isSoftwareUpdate { return "Software Update" }
        if isNowPlaying { return "Now Playing" }
        if isCodingAssistants { return "Coding Assistants" }
        return navigation.selection.title
    }
}

/// A coloured rounded square with a white symbol, the icon style of macOS System Settings.
struct SettingsCategoryIcon: View {
    let symbol: String
    let tileColor: Color
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.58, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                shape.fill(fill.gradient)
                    .overlay(shape.strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
            }
            .accessibilityHidden(true)
    }

    /// Plain greys (.gray, .secondary, .primary) become System Settings' grey tile.
    private var fill: Color {
        [Color.gray, .secondary, .primary].contains(tileColor) ? Color(white: 0.56) : tileColor
    }
}
