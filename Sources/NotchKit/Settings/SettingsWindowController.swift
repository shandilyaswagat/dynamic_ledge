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

        var symbol: String {
            switch self {
            case .general: "gear"
            case .appearance: "circle.lefthalf.filled"
            case .activities: "bell.fill"
            case .home: "house.fill"
            case .about: "info.circle.fill"
            case .nowPlaying: "music.note"
            case .codingAssistants: "terminal.fill"
            case .shortcuts: "square.stack.3d.up.fill"
            case .softwareUpdate: "gear"
            }
        }
        var color: Color {
            switch self {
            case .about: .gray
            case .general: .gray
            case .appearance: .primary
            case .nowPlaying: .pink
            case .codingAssistants: .orange
            case .home: .blue
            case .shortcuts: .indigo
            case .softwareUpdate: .gray
            case .activities: .red
            }
        }

        var description: String {
            switch self {
            case .about: "Version, system requirements and software license for Dynamic Ledge."
            case .general: "Manage general settings, software updates, media, and coding assistants."
            case .appearance: "Choose the look and layout of your notch."
            case .nowPlaying: "Choose how music, podcasts and video appear."
            case .codingAssistants: "Manage coding-assistant approvals and connected AI usage."
            case .home: "Choose the features and widgets available from Home."
            case .shortcuts: "Choose Apple Shortcuts to run from Home."
            case .softwareUpdate: "Check for and install Dynamic Ledge updates."
            case .activities: "Manage live activities, timers, and alerts in the notch."
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
        let root = SettingsRootView(model: model, navigation: navigation) { [weak self] in self?.updatePreview() }
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.title = ""
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
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search", text: $search)
                        .textFieldStyle(.plain)
                        .onSubmit { if let first = searchResults.first { open(first) } }
                        .onExitCommand { search = "" }
                    if isSearching {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Clear search")
                    }
                }
                .padding(7)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                if isSearching {
                    if searchResults.isEmpty {
                        VStack(spacing: 6) {
                            Text("No Results").font(.headline)
                            Text("Try a different search.").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                        Spacer()
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
                List(categories, selection: Binding(get: { navigation.selection }, set: { selection in
                    navigation.navigateTo(selection: selection, generalPage: .overview)
                })) { tab in
                    HStack(spacing: 9) {
                        SettingsCategoryIcon(symbol: tab.symbol, tileColor: tab.color, size: 20)
                        Text(tab.title)
                        if tab == .softwareUpdate && isUpdateAvailable {
                            Spacer(minLength: 0)
                            Text("1")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(.red, in: Circle())
                                .accessibilityLabel(Text("One update available"))
                        }
                    }
                    .tag(tab)
                }
                .listStyle(.sidebar)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        } detail: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    MacNavCapsule(
                        canGoBack: navigation.canGoBack,
                        canGoForward: navigation.canGoForward,
                        onBack: { navigation.goBack() },
                        onForward: { navigation.goForward() }
                    )
                    if !isTopLevelOverview {
                        Text(detailTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 8)

                if isSubpage {
                    Text(detailDescription)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }

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
        }
        .onChange(of: navigation.selection) { _, _ in selectionChanged() }
    }

    private var isTopLevelOverview: Bool {
        // General overview is a hub page; Appearance, Home, Activities show their controls directly
        navigation.selection == .general && navigation.generalPage == .overview
    }

    private var isSubpage: Bool {
        isAbout || isSoftwareUpdate || isNowPlaying || isCodingAssistants
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

    private var detailDescription: String {
        if isAbout { return "Version, system requirements and software license for Dynamic Ledge." }
        if isSoftwareUpdate { return "Check for and install Dynamic Ledge updates." }
        if isNowPlaying { return "Choose how music, podcasts and video appear." }
        if isCodingAssistants { return "Manage coding-assistant approvals and connected AI usage." }
        return navigation.selection.description
    }
}

/// A subtly outlined tile with a colored symbol, like macOS Settings.
struct SettingsCategoryIcon: View {
    let symbol: String
    let tileColor: Color
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
        Image(systemName: symbol)
            .font(.system(size: size * 0.65, weight: .medium))
            .foregroundStyle(tileColor == .gray ? Color.secondary : tileColor)
            .frame(width: size, height: size)
            .background {
                shape.fill(LinearGradient(colors: scheme == .dark
                    ? [Color(white: 0.20), Color(white: 0.07)]
                    : [Color(white: 0.98), Color(white: 0.87)],
                    startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(.primary.opacity(scheme == .dark ? 0.25 : 0.18), lineWidth: 0.7))
            }
            .accessibilityHidden(true)
    }
}

/// A unified segmented capsule navigation control matching macOS System Settings.
private struct MacNavCapsule: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var isBackHovered = false
    @State private var isForwardHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(canGoBack ? Color.primary : Color.secondary.opacity(0.32))
                    .frame(width: 35.5, height: 36)
                    .background(
                        isBackHovered && canGoBack
                            ? Color.primary.opacity(scheme == .dark ? 0.08 : 0.05)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoBack)
            .keyboardShortcut("[", modifiers: .command)
            .help("Back (⌘[)")
            .onHover { isBackHovered = $0 }

            Rectangle()
                .fill(Color.primary.opacity(scheme == .dark ? 0.16 : 0.12))
                .frame(width: 1, height: 20)

            Button(action: onForward) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(canGoForward ? Color.primary : Color.secondary.opacity(0.32))
                    .frame(width: 35.5, height: 36)
                    .background(
                        isForwardHovered && canGoForward
                            ? Color.primary.opacity(scheme == .dark ? 0.08 : 0.05)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canGoForward)
            .keyboardShortcut("]", modifiers: .command)
            .help("Forward (⌘])")
            .onHover { isForwardHovered = $0 }
        }
        .frame(width: 72, height: 36)
        .background {
            let shape = Capsule()
            shape
                .fill(scheme == .dark
                    ? Color(white: 0.12).opacity(0.7)
                    : Color(white: 0.95))
                .overlay(
                    shape
                        .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.18 : 0.12), lineWidth: 0.75)
                )
        }
    }
}
