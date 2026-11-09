import AppKit
import ServiceManagement
import SwiftUI

/// Coloured rounded-square icon used by System Settings rows.
private struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        SettingsCategoryIcon(symbol: symbol, tileColor: color, size: 20)
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

/// The icon tile for General's navigation rows.
private struct GeneralRowIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        SettingsCategoryIcon(symbol: symbol, tileColor: color, size: 20)
    }
}

// MARK: General

struct GeneralSettingsView: View {
    @Bindable var settings: SettingsStore
    let updater: Updater
    let openAbout: () -> Void
    let openSoftwareUpdate: () -> Void
    let openNowPlaying: () -> Void
    let openCodingAssistants: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var needsApproval = SMAppService.mainApp.status == .requiresApproval
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    SettingsCategoryIcon(symbol: "gearshape.fill", tileColor: .gray, size: 52)
                    Text("General")
                        .font(.system(size: 22, weight: .bold))
                    Text("Manage your setup and preferences for Dynamic Ledge, including startup, software updates, media, and coding assistants.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
            }
            Section {
                Button(action: openAbout) {
                    HStack(spacing: 10) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable()
                            .frame(width: 22, height: 22)
                            .accessibilityHidden(true)
                        Text("About")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button(action: openSoftwareUpdate) {
                    HStack(spacing: 10) {
                        GeneralRowIcon(symbol: "arrow.down.circle.fill", color: .blue)
                        Text("Software Update")
                        Spacer()
                        if updater.availableRelease != nil {
                            Text("1")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(.red, in: Circle())
                                .accessibilityLabel(Text("One update available"))
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button(action: openNowPlaying) {
                    HStack(spacing: 10) {
                        GeneralRowIcon(symbol: "music.note", color: .pink)
                        Text("Now Playing")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button(action: openCodingAssistants) {
                    HStack(spacing: 10) {
                        GeneralRowIcon(symbol: "terminal.fill", color: .orange)
                        Text("Coding Assistants")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
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

            Section {
                HStack(spacing: 16) {
                    openModeCard(mode: .click, title: "Click", isSelected: settings.notchOpenMode == .click)
                    openModeCard(mode: .hover, title: "Hover", isSelected: settings.notchOpenMode == .hover)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                if settings.notchOpenMode == .hover {
                    Picker("Hover delay", selection: $settings.hoverDelay) {
                        ForEach(SettingsStore.hoverDelayChoices, id: \.self) { delay in
                            Text(SettingsStore.hoverDelayLabel(delay)).tag(delay)
                        }
                    }
                }
            } header: {
                Text("Open Notch With")
            } footer: {
                Text(settings.notchOpenMode == .click
                    ? "Click the notch to open it."
                    : "Hold the pointer over the notch briefly to open it. Clicking still opens it immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Show when idle", isOn: $settings.showWhenIdle)
                Toggle("Collapse when the pointer leaves", isOn: $settings.collapseOnPointerExit)
                Toggle("Haptic feedback", isOn: $settings.hapticsEnabled)
                Toggle("Keyboard shortcuts (⌃⌥ + a letter)", isOn: $settings.keyboardShortcutsEnabled)
            }
        }
        .formStyle(.grouped)
        // The switch can also change in System Settings; pick that up whenever the tab shows.
        .onAppear { syncLaunchAtLogin() }
    }

    private func openModeCard(mode: NotchOpenMode, title: LocalizedStringKey, isSelected: Bool) -> some View {
        Button {
            settings.notchOpenMode = mode
            Haptics.perform(enabled: settings.hapticsEnabled)
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                        .frame(width: 140, height: 86)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 2.5 : 1)
                        )
                        .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : .clear, radius: 4)

                    // Notch representation
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.85))
                        .frame(width: mode == .click ? 64 : 80, height: mode == .click ? 20 : 26)

                    // Interaction diagram
                    if mode == .click {
                        VStack(spacing: 0) {
                            Spacer()
                            ZStack {
                                Circle()
                                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                                Image(systemName: "cursorarrow.click.2")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                                    .offset(x: 4, y: 4)
                            }
                            .offset(y: -14)
                        }
                    } else {
                        VStack(spacing: 0) {
                            Spacer()
                            ZStack {
                                HStack(spacing: 3) {
                                    ForEach(0..<3, id: \.self) { _ in
                                        Circle()
                                            .fill(Color.accentColor.opacity(0.5))
                                            .frame(width: 3, height: 3)
                                    }
                                }
                                .offset(y: -14)

                                Image(systemName: "cursorarrow.motionlines")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                                    .offset(x: 2, y: 2)
                            }
                            .offset(y: -14)
                        }
                    }
                }

                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.6), lineWidth: isSelected ? 4.5 : 1.2)
                            .frame(width: 14, height: 14)
                    }
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }


    private func settingsLink(_ title: LocalizedStringKey, symbol: String, color: Color = .gray) -> some View {
        HStack(spacing: 10) {
            SettingsIcon(symbol: symbol, color: color)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
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
                HStack(spacing: 24) {
                    themeCard(title: "Black", theme: .black, isSelected: settings.appearance.theme == .black)
                    themeCard(title: "Glass", theme: .glass, isSelected: settings.appearance.theme == .glass)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)

                Toggle("Liquid animations", isOn: $settings.liquidAnimations)
                Picker("Motion", selection: $settings.motionStyle) {
                    Text("Springy").tag(MotionStyle.springy)
                    Text("Standard").tag(MotionStyle.standard)
                    Text("Calm").tag(MotionStyle.calm)
                }
                .pickerStyle(.segmented)
                if settings.appearance.theme == .glass {
                    LabeledContent("Glass Tint") {
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
                Text("Theme")
            } footer: {
                Text(settings.appearance.theme == .glass
                    ? "Frosted glass that blurs what’s behind it, with softer, springier motion. The part around the camera stays black. More tint is easier to read over bright windows."
                    : "The notch itself grows to show what’s happening. Pitch black removes the shadow and outline so the extension is indistinguishable from the notch. On a screen without a notch, it appears in the same spot at the top.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 24) {
                    layoutCard(title: "Standard", elongated: false, isSelected: settings.appearance.nookLayout == .standard)
                    layoutCard(title: "Elongated", elongated: true, isSelected: settings.appearance.nookLayout == .elongated)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            } header: {
                Text("Home Layout")
            } footer: {
                Text("Standard keeps Home compact. Elongated stretches Home, Tray and Clipboard across the screen. Choose which features appear in Home & Widgets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 24) {
                    externalCard(title: "Notch", style: .notch, isSelected: settings.appearance.externalStyle == .notch)
                    externalCard(title: "Pill", style: .pill, isSelected: settings.appearance.externalStyle == .pill)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            } header: {
                Text("Displays Without a Notch")
            } footer: {
                Text(settings.appearance.externalStyle == .pill
                    ? "External displays, and Macs without a notch, show a floating pill just below the top edge, like the Dynamic Island. A MacBook's own notch always stays a notch."
                    : "External displays, and Macs without a notch, get a notch of their own at the top centre, the size of a MacBook's.")
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

    private func themeCard(title: LocalizedStringKey, theme: NotchTheme, isSelected: Bool) -> some View {
        AppearanceChoice(title: title, isSelected: isSelected) {
            settings.appearance.theme = theme
            Haptics.perform(enabled: settings.hapticsEnabled)
        } preview: {
            MiniScreen {
                MiniNotch(width: 92, height: 40, theme: theme, tint: settings.appearance.glassTint) {
                    MiniNowPlaying()
                }
            }
        }
    }

    private func layoutCard(title: LocalizedStringKey, elongated: Bool, isSelected: Bool) -> some View {
        AppearanceChoice(title: title, isSelected: isSelected) {
            settings.appearance.nookLayout = elongated ? .elongated : .standard
            Haptics.perform(enabled: settings.hapticsEnabled)
        } preview: {
            MiniScreen {
                MiniNotch(width: elongated ? 124 : 80, height: elongated ? 30 : 44, theme: settings.appearance.theme, tint: settings.appearance.glassTint) {
                    MiniWidgets(count: elongated ? 4 : 2, columns: elongated ? 4 : 2)
                }
            }
        }
    }

    private func externalCard(title: LocalizedStringKey, style: ExternalDisplayStyle, isSelected: Bool) -> some View {
        AppearanceChoice(title: title, isSelected: isSelected) {
            settings.appearance.externalStyle = style
            Haptics.perform(enabled: settings.hapticsEnabled)
        } preview: {
            MiniScreen {
                if style == .pill {
                    MiniPill(theme: settings.appearance.theme, tint: settings.appearance.glassTint)
                } else {
                    MiniNotch(width: 64, height: 13, theme: settings.appearance.theme, tint: settings.appearance.glassTint, compact: true) {
                        MiniCompactActivity()
                    }
                }
            }
        }
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

struct NowPlayingSettingsView: View {
    @Bindable var settings: SettingsStore
    let nowPlaying: NowPlayingService

    var body: some View {
        Form {
            Section {
                IconToggle(title: "Now Playing", detail: "Music, podcasts and video from any app, or just the ones you pick", symbol: "music.note", color: .pink, isOn: $settings.nowPlayingEnabled)
                if settings.nowPlayingEnabled {
                    IconToggle(title: "Lyrics", detail: "Timed lyrics under the song, when available. The song name and artist are looked up on lrclib.net", symbol: "quote.bubble.fill", color: .pink, isOn: $settings.lyricsEnabled)
                    if SystemAudioTap.isSupported {
                        IconToggle(title: "Live music bars", detail: "The bars move with the music. Dynamic Ledge measures your Mac's sound while something plays; nothing is recorded or sent. macOS asks for access once", symbol: "waveform", color: .pink, isOn: $settings.liveMusicBars)
                    }
                }
                if !nowPlaying.isAvailable {
                    Text("Now Playing isn’t available on this Mac.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if settings.nowPlayingEnabled {
                NowPlayingAppsSection(settings: settings)
                Section {
                    Picker("Keep paused media for", selection: $settings.pausedMediaLinger) {
                        ForEach(SettingsStore.lingerChoices, id: \.self) { seconds in
                            Text(Self.label(for: seconds)).tag(seconds)
                        }
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

struct CodingAssistantSettingsView: View {
    @Bindable var settings: SettingsStore
    let aiUsage: AIUsageService

    var body: some View {
        Form {
            CodingAssistantSection(settings: settings)
            AIUsageSettingsSection(settings: settings, aiUsage: aiUsage)
        }
        .formStyle(.grouped)
    }
}

struct ActivitiesSettingsView: View {
    @Bindable var settings: SettingsStore
    var body: some View {
        Form {
            Section("Live Activities") {
                IconToggle(title: "Timer", detail: "Start one from the notch or the menu bar", symbol: "timer", color: .orange, isOn: $settings.timerEnabled)
                IconToggle(title: "Calls & Microphone", detail: "FaceTime, Zoom, Meet and any app using the mic", symbol: "phone.fill", color: .green, isOn: $settings.callsEnabled)
                IconToggle(title: "AirDrop", detail: "Drag files to the notch to send them", symbol: "dot.radiowaves.up.forward", color: .blue, isOn: $settings.airDropEnabled)
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
            Section("Alerts") {
                IconToggle(title: "Charging", detail: nil, symbol: "bolt.fill", color: .green, isOn: $settings.chargingAlertsEnabled)
                IconToggle(title: "Low Battery", detail: "At 20% and 10%", symbol: "battery.25percent", color: .red, isOn: $settings.lowBatteryAlertsEnabled)
                IconToggle(title: "Volume & Brightness", detail: "Shows the level in the notch when you change it", symbol: "speaker.wave.2.fill", color: .indigo, isOn: $settings.levelsEnabled)
            }
        }
        .formStyle(.grouped)
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
            Toggle(isOn: $settings.agentFinishedAlerts) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tell me when it's done")
                    Text("A short alert when Claude Code, Codex or Cursor finishes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!settings.agentApprovals.contains(where: \.reportsFinishing))
            Toggle(isOn: $settings.agentWatchesTranscript) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Close when answered in Claude Code")
                    Text("Reads new lines of that session's transcript on this Mac while a request waits")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!settings.agentApprovals.contains(.claude))
        } header: {
            Text("Approvals")
        } footer: {
            Text("When an assistant wants to run a command or change a file, the notch shows what it wants to do, with Allow and Deny. Close it, or wait two minutes, and the assistant asks in its own window as usual. With Close when answered in Claude Code on, answering in Claude Code's own window closes the request in the notch too. Questions and plans stay in the assistant's window. Switching one on adds a hook to that assistant’s settings file (Claude Code, Codex and Cursor get a second one that says when they finish); switching it off removes them. New sessions pick it up. Codex asks you to review new hooks once: type /hooks in Codex.")
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
                    try AgentHookSettings.install(kind, command: command, finished: settings.agentFinishedAlerts)
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

private struct AIUsageSettingsSection: View {
    @Bindable var settings: SettingsStore
    let aiUsage: AIUsageService

    var body: some View {
        Section {
            IconToggle(
                title: "AI Agent Usage",
                detail: "How much of Codex's and Antigravity's limits you've used, and when they reset",
                symbol: "sparkles",
                color: .purple,
                isOn: $settings.aiUsageEnabled
            )
        } header: {
            Text("AI Agent Usage")
        } footer: {
            Text("Off until you turn it on. Codex checks your limits with OpenAI using its own sign-in; Antigravity's are read on this Mac. Dynamic Ledge sends nothing itself and needs no API keys. Claude Code isn't listed: it keeps your limits only on Anthropic's servers, which would mean using your Claude sign-in.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if settings.aiUsageEnabled {
            Section {
                provider(.codex, isOn: $settings.aiUsageCodexEnabled)
                provider(.antigravity, isOn: $settings.aiUsageAntigravityEnabled)
            } header: {
                Text("Assistants")
            } footer: {
                Text("Every 5 minutes, Dynamic Ledge checks the assistants you tick. Only the ones it can reach appear in the notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $settings.aiUsageInNotch) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Show in the notch")
                        Text("The lowest limit left shows beside the camera when nothing else is on. Off stops the checks. The AI Agent Usage tile turns this on and off too.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Show in Home", isOn: $settings.aiUsageShowHomeWidget)
                    .disabled(!settings.aiUsageInNotch)
                Button("Refresh Now") { aiUsage.refreshAll(userInitiated: true) }
                    .disabled(aiUsage.isRefreshing)
            }
        }
    }

    private func provider(_ provider: AIProvider, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(provider.displayName)
                Text(provider.integrationNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let usage = aiUsage.usages[provider] {
                    Text(usage.status.statusDescription)
                        .font(.caption)
                        .foregroundStyle(usage.status.isSuccess ? .green : .secondary)
                }
            }
        }
        .onChange(of: isOn.wrappedValue) { _, enabled in
            if enabled { aiUsage.refreshAll(userInitiated: false) }
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
                if settings.clipboardEnabled {
                    IconToggle(title: "Text from images", detail: "When you copy an image, its text is read on this Mac and added to Clipboard. The image isn't kept", symbol: "text.viewfinder", color: .orange, isOn: $settings.clipboardReadsImages)
                }
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

struct ShortcutsSettingsView: View {
    @Bindable var settings: SettingsStore
    let shortcuts: ShortcutsService
    var body: some View {
        Form {
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
    private static let repository = URL(string: "https://github.com/shandilyaswagat/dynamic_ledge")!
    private static let website = URL(string: "https://talvioh.vercel.app")!
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                    Text("Dynamic Ledge")
                        .font(.system(size: 22, weight: .bold))
                    Text("Live activities for your Mac’s notch.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section {
                LabeledContent("Version", value: version)
                    .textSelection(.enabled)
                LabeledContent("Requires", value: "macOS \(info["LSMinimumSystemVersion"] as? String ?? "14.0") or later")
                LabeledContent("Made for", value: "Apple silicon and Intel Macs")
            }

            Section {
                link("Website", detail: "talvioh.vercel.app", destination: Self.website)
                link("Report a Problem", detail: "GitHub Issues", destination: Self.repository.appending(path: "issues"))
                link("License", detail: "GNU GPL 3.0", destination: Self.repository.appending(path: "blob/main/LICENSE"))
            } footer: {
                Text(info["NSHumanReadableCopyright"] as? String ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
    }

    /// "1.4.2 (79)", like About This Mac.
    private var version: String {
        let short = info["CFBundleShortVersionString"] as? String ?? "–"
        guard let build = info["CFBundleVersion"] as? String, build != short else { return short }
        return "\(short) (\(build))"
    }

    private func link(_ title: LocalizedStringKey, detail: String, destination: URL) -> some View {
        Link(destination: destination) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(detail).foregroundStyle(.secondary)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Update state and controls follow the layout in macOS System Settings.
struct SoftwareUpdateSettingsView: View {
    @Bindable var settings: SettingsStore
    let updater: Updater

    var body: some View {
        Form {
            Section {
                HStack(alignment: .center, spacing: 14) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dynamic Ledge")
                            .font(.headline)
                        if let current = updater.currentVersion {
                            Text("Version \(current.description)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    updateStatusTrailing
                }
                .padding(.vertical, 4)

                if case .available(let release) = updater.state {
                    VStack(alignment: .leading, spacing: 6) {
                        Divider()
                            .padding(.vertical, 4)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Dynamic Ledge \(release.version.description)")
                                    .font(.headline)
                                Text("1 update available")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(updater.canInstallInPlace(release) ? "Update Now" : "Download") {
                                updater.install(release)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            Section {
                Toggle("Check for updates automatically", isOn: $settings.checksForUpdates)
                Toggle("Install updates automatically", isOn: $settings.installsUpdatesAutomatically)
                    .disabled(!settings.checksForUpdates)
            } header: {
                Text("Automatic Updates")
            } footer: {
                Text("Checks for updates automatically in the background. When enabled, verified updates install and Dynamic Ledge relaunches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if case .idle = updater.state { updater.check() }
        }
    }

    @ViewBuilder
    private var updateStatusTrailing: some View {
        switch updater.state {
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking for updates…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .upToDate:
            HStack(spacing: 12) {
                Text("Up to date")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Check for Updates") { updater.check() }
                    .controlSize(.small)
            }
        case .available:
            EmptyView()
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installing…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            VStack(alignment: .trailing, spacing: 2) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Try Again") { updater.check() }
                    .controlSize(.small)
            }
        case .idle:
            Button("Check for Updates") { updater.check() }
                .controlSize(.small)
        }
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

// MARK: Appearance previews

/// A preview card with a radio-style label, as in System Settings' Appearance.
private struct AppearanceChoice<Preview: View>: View {
    let title: LocalizedStringKey
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview()
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.15), lineWidth: isSelected ? 2.5 : 1)
                    )
                HStack(spacing: 6) {
                    Circle()
                        .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.6), lineWidth: isSelected ? 4.5 : 1.2)
                        .frame(width: 14, height: 14)
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A small desktop: wallpaper and a menu bar, with whatever the notch shows at the top centre.
private struct MiniScreen<Content: View>: View {
    @ViewBuilder let content: () -> Content

    static var wallpaper: some View {
        LinearGradient(
            colors: [Color(red: 0.16, green: 0.42, blue: 0.78), Color(red: 0.55, green: 0.32, blue: 0.70), Color(red: 0.95, green: 0.55, blue: 0.45)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            Self.wallpaper
            Rectangle().fill(.white.opacity(0.18)).frame(height: 7)
            content()
        }
        .frame(width: 150, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// The notch as the app draws it: fused to the top edge, with concave shoulders and a rounded
/// bottom, in black or in smoked glass.
private struct MiniNotch<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    let theme: NotchTheme
    let tint: Double
    var compact = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        let flare: CGFloat = compact ? 3 : 4
        let shape = IslandShape(topRadius: 0, bottomRadius: compact ? 5 : 10, flare: flare)
        ZStack(alignment: .top) {
            if theme == .glass && !compact {
                MiniGlass(shape: shape, tint: tint, camera: 7 / height)
            } else {
                shape.fill(.black)
            }
            content()
                .padding(.top, compact ? 0 : 9)
                .padding(.horizontal, flare + (compact ? 4 : 7))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: compact ? .center : .top)
        }
        .frame(width: width + 2 * flare, height: height)
    }
}

/// The floating pill: round ends, a little below the top edge.
private struct MiniPill: View {
    let theme: NotchTheme
    let tint: Double

    var body: some View {
        Capsule()
            .fill(.black)
            .frame(width: 62, height: 15)
            .overlay { MiniCompactActivity().padding(.horizontal, 7) }
            .padding(.top, 3)
    }
}

/// The Glass theme in miniature: black at the camera and through the body, easing into frosted,
/// tinted glass along the bottom, with a light lip, like `GlassSurface`.
private struct MiniGlass<S: Shape>: View {
    let shape: S
    let tint: Double
    /// Share of the height covered by the camera band.
    let camera: Double

    var body: some View {
        let bottom = 0.08 + 0.5 * tint
        ZStack {
            MiniScreen<EmptyView>.wallpaper.blur(radius: 6)
            Color.white.opacity(0.10)
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: camera),
                .init(color: .black.opacity(0.93), location: 0.6),
                .init(color: .black.opacity(bottom), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            LinearGradient(stops: [
                .init(color: .white.opacity(0), location: 0.8),
                .init(color: .white.opacity(0.18), location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .clipShape(shape)
        .overlay(shape.stroke(LinearGradient(colors: [.clear, .white.opacity(0.35)], startPoint: .top, endPoint: .bottom), lineWidth: 0.6))
    }
}

/// Artwork, title and a progress bar, like the music view.
private struct MiniNowPlaying: View {
    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(.white.opacity(0.9)).frame(width: 34, height: 3)
                Capsule().fill(.white.opacity(0.45)).frame(width: 24, height: 3)
                Capsule().fill(.white.opacity(0.3)).frame(height: 2)
            }
        }
    }
}

/// Widget tiles, as in Home.
private struct MiniWidgets: View {
    let count: Int
    let columns: Int

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
            ForEach(0..<count, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(.white.opacity(0.22))
                    .frame(height: 14)
            }
        }
    }
}

/// A compact live activity: artwork on the left, a level on the right.
private struct MiniCompactActivity: View {
    var body: some View {
        HStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom))
                .frame(width: 8, height: 8)
            Spacer(minLength: 0)
            HStack(spacing: 1.5) {
                ForEach([4.0, 7, 5, 8], id: \.self) { height in
                    Capsule().fill(Color.green).frame(width: 1.5, height: height)
                }
            }
        }
    }
}
