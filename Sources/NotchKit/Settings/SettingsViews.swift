import AppKit
import ServiceManagement
import SwiftUI

/// Coloured rounded-square icon used by System Settings rows.
private struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(color.gradient))
    }
}

private struct IconToggle: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    let symbol: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 10) {
                SettingsIcon(symbol: symbol, color: color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: General

struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var needsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if needsApproval {
                    HStack {
                        Text("Allow Dynamic Ledge in Login Items to finish.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                            .controlSize(.small)
                    }
                }
                if let launchError {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle("Show in menu bar", isOn: $settings.showMenuBarIcon)
                Picker("Display", selection: $settings.display) {
                    Text("Built-in display").tag(DisplayChoice.automatic)
                    Text("Main display").tag(DisplayChoice.main)
                    Text("Follow the pointer").tag(DisplayChoice.followPointer)
                    Divider()
                    ForEach(DisplayOption.connected) { option in
                        Text(option.name).tag(DisplayChoice.specific(option.uuid))
                    }
                    if case .specific(let uuid) = settings.display, !DisplayOption.connected.contains(where: { $0.uuid == uuid }) {
                        Text("Saved display (not connected)").tag(settings.display)
                    }
                    Divider()
                    Text("All displays").tag(DisplayChoice.all)
                }
            } footer: {
                Text("Built-in display keeps it on your MacBook's notch. Pick a screen by name to keep it there, or All displays to show it on every screen: music, timers and alerts appear everywhere, and what you open shows on the screen you're using. Screens without a notch get a notch of their own at the top, which stays out of sight until something's showing or you rest the pointer on its spot. When the menu bar icon is hidden, open Dynamic Ledge again from Applications to get back here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if LockScreenController.isAvailable {
                Section {
                    Toggle("Show on Lock Screen", isOn: $settings.lockScreenEnabled)
                } footer: {
                    Text("While your Mac is locked, the notch shows a running timer, what's playing, or charging, just as it looks when you're logged in. Anyone at your Mac can see it, so it's off until you turn it on.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Behavior") {
                Toggle("Show when idle", isOn: $settings.showWhenIdle)
                Picker("Open notch with", selection: $settings.notchOpenMode) {
                    Text("Click").tag(NotchOpenMode.click)
                    Text("Hover").tag(NotchOpenMode.hover)
                }
                .pickerStyle(.segmented)
                if settings.notchOpenMode == .hover {
                    Picker("Hover delay", selection: $settings.hoverDelay) {
                        ForEach(SettingsStore.hoverDelayChoices, id: \.self) { delay in
                            Text(SettingsStore.hoverDelayLabel(delay)).tag(delay)
                        }
                    }
                }
                Text(settings.notchOpenMode == .click
                    ? "Click the notch to open it."
                    : "Hold the pointer over the notch briefly to open it. Clicking still opens it immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Collapse when the pointer leaves", isOn: $settings.collapseOnPointerExit)
                Toggle("Liquid animations", isOn: $settings.liquidAnimations)
                Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
                Toggle("Keyboard shortcuts (⌃⌥ + a letter)", isOn: $settings.keyboardShortcutsEnabled)
            }

            Section {
                Toggle("Play a sound when a timer ends", isOn: $settings.timerSound)
                Picker("Focus session", selection: $settings.focusMinutes) {
                    ForEach(SettingsStore.focusChoices, id: \.self) { Text("\($0) minutes").tag($0) }
                }
                Picker("Break", selection: $settings.breakMinutes) {
                    ForEach(SettingsStore.breakChoices, id: \.self) { Text("\($0) minutes").tag($0) }
                }
            } header: {
                Text("Timer")
            } footer: {
                Text("Focus in Home starts a session. When it ends, the notch offers a break, then the next session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // The switch can also change in System Settings; pick that up whenever the tab shows.
        .onAppear { syncLaunchAtLogin() }
    }

    private func syncLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        needsApproval = status == .requiresApproval
        let enabled = status == .enabled || status == .requiresApproval
        if launchAtLogin != enabled {
            launchAtLogin = enabled
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let status = SMAppService.mainApp.status
        let isOn = status == .enabled || status == .requiresApproval
        guard enabled != isOn else { return }
        defer { needsApproval = SMAppService.mainApp.status == .requiresApproval }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchError = nil
        } catch {
            launchError = String(localized: "Couldn’t change this setting: \(error.localizedDescription)")
            let actual = SMAppService.mainApp.status == .enabled
            if actual != enabled {
                launchAtLogin = actual
            }
        }
    }
}

// MARK: Appearance

struct AppearanceSettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Home layout", selection: $settings.appearance.nookLayout) {
                    Text("Standard").tag(NookLayout.standard)
                    Text("Elongated").tag(NookLayout.elongated)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Elongated stretches Home, Tray and Clipboard across the top of the screen, with your widgets in one long row you can scroll sideways.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Theme", selection: $settings.appearance.theme) {
                    Text("Black").tag(NotchTheme.black)
                    Text("Glass").tag(NotchTheme.glass)
                }
                .pickerStyle(.segmented)
                if settings.appearance.theme == .glass {
                    LabeledContent("Glass") {
                        HStack(spacing: 8) {
                            Text("Clear").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $settings.appearance.glassTint, in: NotchAppearance.glassTintRange)
                                .frame(minWidth: 180)
                            Text("Tinted").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Toggle("Pitch black", isOn: $settings.appearance.pitchBlack)
                }
            } header: {
                Text("Look")
            } footer: {
                Text(settings.appearance.theme == .glass
                    ? "Frosted glass that blurs what’s behind it, with softer, springier motion. The part around the camera stays black. More tint is easier to read over bright windows."
                    : "The notch itself grows to show what’s happening. Pitch black removes the shadow and outline so the extension is indistinguishable from the notch. On a screen without a notch, it appears in the same spot at the top.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Size", selection: $settings.appearance.size) {
                    Text("Small").tag(NotchSize.small)
                    Text("Medium").tag(NotchSize.medium)
                    Text("Large").tag(NotchSize.large)
                }
                .pickerStyle(.segmented)
                slider("Width", value: $settings.appearance.width, range: NotchAppearance.widthRange, step: 2)
                slider("Thickness", value: $settings.appearance.height, range: NotchAppearance.heightRange, step: 1)
            } header: {
                Text("Size")
            } footer: {
                Text("Size scales everything the notch shows. Width and thickness fine-tune the compact shape; thickness never goes below the height of the notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("The shape stays visible while this tab is open, so you can see each change.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults") { settings.resetAppearance() }
                        .disabled(settings.appearance == .standard)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Continuous slider (a stepped one draws a tick per step) that stores rounded values.
    private func slider(_ title: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        let rounded = Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = (($0 / step).rounded() * step) }
        )
        return LabeledContent {
            HStack(spacing: 10) {
                Slider(value: rounded, in: range)
                    .frame(minWidth: 200)
                Text("\(Int(value.wrappedValue.rounded())) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }
}

// MARK: Activities

struct ActivitiesSettingsView: View {
    @Bindable var settings: SettingsStore
    let nowPlaying: NowPlayingService

    var body: some View {
        Form {
            Section("Live Activities") {
                IconToggle(title: "Now Playing", detail: "Music, podcasts and video from any app, or just the ones you pick", symbol: "music.note", color: .pink, isOn: $settings.nowPlayingEnabled)
                if settings.nowPlayingEnabled {
                    IconToggle(title: "Lyrics", detail: "Timed lyrics under the song, when it has them. The song’s name and artist are looked up on lrclib.net", symbol: "quote.bubble.fill", color: .pink, isOn: $settings.lyricsEnabled)
                }
                if !nowPlaying.isAvailable {
                    Text("Now Playing isn’t available on this Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                IconToggle(title: "Timer", detail: "Start one from the notch or the menu bar", symbol: "timer", color: .orange, isOn: $settings.timerEnabled)
                IconToggle(title: "Calls & Microphone", detail: "FaceTime, Zoom, Meet and any app using the mic", symbol: "phone.fill", color: .green, isOn: $settings.callsEnabled)
                IconToggle(title: "AirDrop", detail: "Drag files to the notch to send them", symbol: "dot.radiowaves.up.forward", color: .blue, isOn: $settings.airDropEnabled)
            }

            if settings.nowPlayingEnabled {
                NowPlayingAppsSection(settings: settings)
            }

            CodingAssistantSection(settings: settings)

            Section("Alerts") {
                IconToggle(title: "Charging", detail: nil, symbol: "bolt.fill", color: .green, isOn: $settings.chargingAlertsEnabled)
                IconToggle(title: "Low Battery", detail: "At 20% and 10%", symbol: "battery.25percent", color: .red, isOn: $settings.lowBatteryAlertsEnabled)
                IconToggle(title: "Volume & Brightness", detail: "Shows the level in the notch when you change it", symbol: "speaker.wave.2.fill", color: .indigo, isOn: $settings.levelsEnabled)
            }

            Section {
                Picker("Keep paused media for", selection: $settings.pausedMediaLinger) {
                    ForEach(SettingsStore.lingerChoices, id: \.self) { seconds in
                        Text(Self.label(for: seconds)).tag(seconds)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private static func label(for seconds: TimeInterval) -> String {
        seconds < 60 ? "\(Int(seconds)) seconds" : (seconds == 60 ? "1 minute" : "\(Int(seconds / 60)) minutes")
    }
}

/// Coding assistants' permission requests, answered from the notch.
private struct CodingAssistantSection: View {
    @Bindable var settings: SettingsStore
    @State private var problem: (kind: AgentKind, text: String)?

    var body: some View {
        Section {
            ForEach(AgentKind.allCases) { kind in
                IconToggle(title: LocalizedStringKey(kind.displayName), detail: LocalizedStringKey(Self.detail(kind)), symbol: Self.symbol(kind), color: .orange, isOn: enabled(kind))
                if let problem, problem.kind == kind {
                    Text(problem.text)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Coding Assistants")
        } footer: {
            Text("When an assistant wants to run a command or change a file, the notch shows what it wants to do, with Allow and Deny. Close it, or wait two minutes, and the assistant asks in its own window as usual. Switching one on adds a hook to that assistant’s settings file; switching it off removes it. New sessions pick it up. Codex asks you to review new hooks once: type /hooks in Codex.")
        }
    }

    private static func detail(_ kind: AgentKind) -> String {
        let file = AgentHookSettings.displayPath(for: kind)
        return kind.asksOnlyWhenNeeded
            ? "Only when it would ask you anyway · \(file)"
            : "Asks before every terminal command · \(file)"
    }

    private static func symbol(_ kind: AgentKind) -> String {
        switch kind {
        case .claude, .codex, .copilot: "terminal.fill"
        case .antigravity, .cursor: "chevron.left.forwardslash.chevron.right"
        }
    }

    private func enabled(_ kind: AgentKind) -> Binding<Bool> {
        Binding {
            settings.agentApprovals.contains(kind)
        } set: { isOn in
            problem = nil
            let file = AgentHookSettings.displayPath(for: kind)
            do {
                if isOn {
                    guard let command = AgentHookSettings.currentCommand(socket: AgentBridge.defaultSocketPath, kind: kind) else { return }
                    try AgentHookSettings.install(kind, command: command)
                    settings.agentApprovals.insert(kind)
                } else {
                    try AgentHookSettings.uninstall(kind)
                    settings.agentApprovals.remove(kind)
                }
            } catch AgentHookSettings.Failure.unreadable {
                problem = (kind, "Couldn’t read \(file), so it was left as it is. Check that it’s valid JSON.")
            } catch {
                problem = (kind, "Couldn’t save \(file).")
            }
        }
    }
}

/// Every app's music, or only the apps ticked here.
private struct NowPlayingAppsSection: View {
    @Bindable var settings: SettingsStore

    /// Offered ticked the first time someone switches to choosing apps, if installed.
    private static let suggested = ["com.spotify.client", "com.apple.Music"]

    var body: some View {
        Section {
            Picker("Show music from", selection: mode) {
                Text("All apps").tag(MediaAppFilter.Mode.all)
                Text("Only these apps").tag(MediaAppFilter.Mode.chosen)
            }
            if settings.nowPlayingAppMode == .chosen {
                ForEach(rows) { app in
                    Toggle(isOn: allowed(app.id)) {
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(app.name)
                        }
                    }
                    .accessibilityLabel(Text(app.name))
                    .contextMenu {
                        Button("Remove from List") { settings.forgetMediaApp(app.id) }
                    }
                }
                Button("Add App…", action: addApp)
            }
        } header: {
            Text("Now Playing Apps")
        } footer: {
            if settings.nowPlayingAppMode == .chosen {
                Text("Music from other apps won’t show in the notch. Apps join this list once they play something. YouTube and other websites play through your browser, so leave the browser off to keep them out.")
            }
        }
    }

    private var mode: Binding<MediaAppFilter.Mode> {
        Binding {
            settings.nowPlayingAppMode
        } set: { newMode in
            if newMode == .chosen, settings.nowPlayingApps.isEmpty {
                for id in Self.suggested where MediaAppInfo.isInstalled(id) {
                    settings.setNowPlaying(id, allowed: true)
                }
            }
            settings.nowPlayingAppMode = newMode
        }
    }

    private func allowed(_ id: String) -> Binding<Bool> {
        Binding {
            settings.nowPlayingApps.contains(id)
        } set: { isOn in
            settings.setNowPlaying(id, allowed: isOn)
        }
    }

    /// Ticked apps first, in the order they were picked, then the rest that played lately.
    private var rows: [MediaAppInfo] {
        var ids = settings.nowPlayingApps
        ids += settings.recentMediaApps.identifiers.filter { !ids.contains($0) && $0 != Bundle.main.bundleIdentifier }
        return ids.map(MediaAppInfo.lookup)
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier {
                settings.setNowPlaying(id, allowed: true)
            }
        }
    }
}

/// An app's name and icon, looked up once per launch.
@MainActor
private struct MediaAppInfo: Identifiable {
    let id: String
    let name: String
    let icon: NSImage

    private static var cache: [String: MediaAppInfo] = [:]

    static func isInstalled(_ id: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    static func lookup(_ id: String) -> MediaAppInfo {
        if let cached = cache[id] { return cached }
        let info: MediaAppInfo
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            info = MediaAppInfo(id: id, name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
        } else {
            // Uninstalled since: still listed, so it can be unticked or removed. Not cached, in
            // case it's installed again.
            return MediaAppInfo(id: id, name: id, icon: NSWorkspace.shared.icon(for: .application))
        }
        cache[id] = info
        return info
    }
}

// MARK: Home

struct HomeSettingsView: View {
    @Bindable var settings: SettingsStore
    let calendar: CalendarService
    let shortcuts: ShortcutsService

    var body: some View {
        Form {
            Section {
                IconToggle(title: "File Tray", detail: "Files you drop on the notch, or saved document windows. Up to 30; clears when the app quits, except pinned ones", symbol: "tray.full.fill", color: .cyan, isOn: $settings.trayEnabled)
                if settings.trayEnabled {
                    Button("Allow document window dragging…") { DocumentWindowDrag.requestAccess() }
                    Text("Enable Dynamic Ledge in macOS Accessibility settings to store a saved document by dragging its whole window to the notch. The source app must expose its saved document location. Some apps also ask for Automation access. Unsaved or ambiguous documents cannot be stored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                IconToggle(title: "Clipboard", detail: "Text you copied recently. Passwords are skipped; only pinned clips are saved", symbol: "doc.on.clipboard.fill", color: .orange, isOn: $settings.clipboardEnabled)
                IconToggle(title: "Notes", detail: "A quick scratchpad, saved as you type", symbol: "note.text", color: .yellow, isOn: $settings.notesEnabled)
                IconToggle(title: "Reminders", detail: "Today's to-dos, ticked off from the notch", symbol: "checklist", color: .blue, isOn: $settings.remindersEnabled)
                IconToggle(title: "Finished downloads", detail: "A heads-up when a file lands in Downloads. macOS asks for access once", symbol: "arrow.down.circle.fill", color: .blue, isOn: $settings.downloadsEnabled)
                IconToggle(title: "Mirror", detail: "A quick camera preview before calls", symbol: "person.crop.square.fill", color: .purple, isOn: $settings.mirrorEnabled)
                IconToggle(title: "Stats", detail: "Memory and CPU beside the camera when nothing else is on, plus disk and network in the grid", symbol: "gauge.with.dots.needle.33percent", color: .green, isOn: $settings.statsEnabled)
            } header: {
                Text("Features")
            } footer: {
                Text("Click the notch to open Home. Up to three of these sit beside Home as shortcuts (Files and Clipboard to start); everything else is in the grid at the top right. To change the shortcuts, open the grid and hold any feature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                IconToggle(title: "Calendar", detail: "Your next event, and a heads-up 5 minutes before it", symbol: "calendar", color: .red, isOn: $settings.calendarEnabled)
                if settings.calendarEnabled {
                    LabeledContent("Access") {
                        switch calendar.access {
                        case .granted:
                            Text("Allowed").foregroundStyle(.secondary)
                        case .notAsked:
                            Button("Connect Calendar") { calendar.requestAccess() }
                        case .denied, .limited:
                            Button("Open Privacy Settings") { calendar.openPrivacySettings() }
                        }
                    }
                }
            } header: {
                Text("Calendar")
            }

            Section {
                IconToggle(title: "Shortcuts", detail: "Run your favourite shortcuts from Home", symbol: "bolt.fill", color: .blue, isOn: $settings.shortcutsEnabled)
                if settings.shortcutsEnabled {
                    if !shortcuts.isSupported {
                        Text("The Shortcuts app isn't available on this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if shortcuts.isLoading && shortcuts.available.isEmpty {
                        ProgressView().controlSize(.small)
                    } else if shortcuts.available.isEmpty {
                        Text("You don't have any shortcuts yet. Make some in the Shortcuts app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(shortcuts.available, id: \.self) { name in
                            let isFavorite = settings.favoriteShortcuts.contains(name)
                            Toggle(name, isOn: Binding(
                                get: { isFavorite },
                                set: { _ in settings.toggleFavorite(name) }
                            ))
                            .disabled(!isFavorite && settings.favoriteShortcuts.count >= SettingsStore.maximumFavoriteShortcuts)
                        }
                    }
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Pick up to \(SettingsStore.maximumFavoriteShortcuts) to show in Home.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { shortcuts.reload() }
    }
}

// MARK: About

struct AboutSettingsView: View {
    @Bindable var settings: SettingsStore
    let updater: Updater

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Dynamic Ledge")
                .font(.system(size: 22, weight: .semibold))
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Live activities for your Mac’s notch.")
                .font(.callout)
                .padding(.top, 4)
            UpdatesBox(settings: settings, updater: updater)
                .padding(.top, 10)
            if let copyright = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String {
                Text(copyright)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            HStack(spacing: 14) {
                Link("Source Code", destination: Self.repository)
                Link("License", destination: Self.repository.appending(path: "blob/main/LICENSE"))
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private static let repository = URL(string: "https://github.com/shandilyaswagat/dynamic_ledge")!
}

/// Updates: the automatic check, a button to check now, and Install when there's something new.
private struct UpdatesBox: View {
    @Bindable var settings: SettingsStore
    let updater: Updater

    var body: some View {
        VStack(spacing: 8) {
            Toggle("Check for updates automatically", isOn: $settings.checksForUpdates)
            HStack(spacing: 10) {
                switch updater.state {
                case .available(let release):
                    Text("Version \(release.version.description) is available.")
                    Button(updater.canInstallInPlace(release) ? "Install and Relaunch" : "Download") { updater.install(release) }
                        .buttonStyle(.borderedProminent)
                case .installing:
                    ProgressView().controlSize(.small)
                    Text("Installing…")
                case .checking:
                    ProgressView().controlSize(.small)
                    Text("Checking…")
                case .upToDate:
                    Text("You're up to date.").foregroundStyle(.secondary)
                    Button("Check Now") { updater.check() }
                case .failed(let message):
                    Text(message).foregroundStyle(.secondary)
                    Button("Try Again") { updater.check() }
                case .idle:
                    Button("Check for Updates") { updater.check() }
                }
            }
            .font(.callout)
            Text("Checking asks GitHub for the latest version.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 380)
    }
}

/// A connected screen, for the Display picker.
struct DisplayOption: Identifiable {
    let uuid: String
    let name: String
    var id: String { uuid }

    @MainActor
    static var connected: [DisplayOption] {
        NSScreen.screens.compactMap { screen in
            IslandWindowController.uuid(screen).map { DisplayOption(uuid: $0, name: screen.localizedName) }
        }
    }
}
