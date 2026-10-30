import AppKit
import Testing
@testable import NotchKit

@MainActor
@Suite("Glass theme")
struct GlassThemeTests {
    @Test func savesThemeAndClampsTint() {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.appearance.theme == .black, "the current look stays the default")
        settings.appearance.theme = .glass
        settings.appearance.glassTint = 7
        let reopened = SettingsStore(defaults: defaults)
        #expect(reopened.appearance.theme == .glass)
        #expect(reopened.appearance.glassTint == 1)
        #expect(NotchAppearance(width: 200, height: 32, glassTint: .nan).clamped().glassTint == NotchAppearance.defaultGlassTint)
    }

    @Test func glassKeepsTheNotchBandAndDropsTheShadow() {
        let screen = ScreenMetrics(size: CGSize(width: 1470, height: 956), notch: CGRect(x: 645, y: 0, width: 180, height: 32), menuBarHeight: 32)
        var appearance = NotchAppearance.standard
        appearance.pitchBlack = false
        appearance.theme = .glass
        let layout = LayoutEngine(screen: screen, appearance: appearance).layout(for: .nook(.home), home: HomeContent(hasMedia: false), hovering: false)
        #expect(layout.notchBand == 32)
        #expect(layout.shadow == 0)

        let virtual = ScreenMetrics(size: CGSize(width: 1920, height: 1080), notch: nil, menuBarHeight: 24)
        let plain = LayoutEngine(screen: virtual, appearance: appearance).layout(for: .nook(.home), home: HomeContent(hasMedia: false), hovering: false)
        #expect(plain.notchBand == 0, "no camera to hide on a screen without a notch")
    }
}

@Suite("Download progress")
struct DownloadProgressTests {
    @Test func namesDropTheTemporaryExtension() {
        #expect(DownloadProgressItem.displayName(for: URL(fileURLWithPath: "/D/report.pdf.crdownload")) == "report.pdf")
        #expect(DownloadProgressItem.displayName(for: URL(fileURLWithPath: "/D/movie.mov.download")) == "movie.mov")
        #expect(DownloadProgressItem.displayName(for: URL(fileURLWithPath: "/D/setup.dmg")) == "setup.dmg")
        #expect(DownloadProgressItem.displayName(for: URL(fileURLWithPath: "/D/.part")) == ".part")
    }

    @Test func summaryAddsUpKnownSizes() {
        let now = Date()
        let summary = DownloadSummary([
            DownloadProgressItem(id: "a", name: "a", completed: 50, total: 100, secondsLeft: 10, startedAt: now),
            DownloadProgressItem(id: "b", name: "b", completed: 300, total: 300, secondsLeft: 40, startedAt: now),
            DownloadProgressItem(id: "c", name: "c", completed: 999, total: 0, startedAt: now),
        ])
        #expect(summary.fraction == 350.0 / 400.0)
        #expect(summary.secondsLeft == 40)
        #expect(DownloadSummary([DownloadProgressItem(id: "c", name: "c", completed: 5, total: -1, startedAt: now)]).fraction == nil)
        #expect(DownloadProgressItem(id: "d", name: "d", completed: 150, total: 100, startedAt: now).fraction == 1)
    }

    @Test func rateSmoothsAndEstimates() {
        var rate = DownloadRate()
        let start = Date()
        rate.add(bytes: 0, at: start)
        #expect(rate.bytesPerSecond == nil)
        rate.add(bytes: 1_000, at: start.addingTimeInterval(1))
        #expect(rate.bytesPerSecond == 1_000)
        rate.add(bytes: 4_000, at: start.addingTimeInterval(2))
        #expect(abs((rate.bytesPerSecond ?? 0) - 1_600) < 0.001)
        #expect(abs((rate.secondsLeft(completed: 4_000, total: 20_000) ?? 0) - 10) < 0.001)
        #expect(rate.secondsLeft(completed: 4_000, total: 0) == nil)
        rate.add(bytes: 100, at: start.addingTimeInterval(3))
        #expect(abs((rate.bytesPerSecond ?? 0) - 1_600) < 0.001, "a restarted download doesn't make the speed negative")
    }

    @Test func formatsSizesAndTimes() {
        #expect(DownloadFormat.timeLeft(4) == "4 sec left")
        #expect(DownloadFormat.timeLeft(0.2) == "1 sec left")
        #expect(DownloadFormat.timeLeft(150) == "3 min left")
        #expect(DownloadFormat.timeLeft(3_900) == "1 hr 5 min left")
        #expect(DownloadFormat.bytes(0, of: 0).isEmpty == false)
        #expect(DownloadFormat.bytes(1_000_000, of: 2_000_000).contains(" of "))
    }

    @MainActor
    @Test func followsAPublishedDownload() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let monitor = DownloadProgressMonitor(folder: folder)
        monitor.start()
        defer { monitor.stop() }

        let file = folder.appendingPathComponent("big.zip.crdownload")
        FileManager.default.createFile(atPath: file.path, contents: Data())
        let progress = Progress(totalUnitCount: 1_000)
        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.fileURL = file
        progress.publish()
        defer { progress.unpublish() }
        progress.completedUnitCount = 250

        var seen: DownloadProgressItem?
        for _ in 0..<40 where seen == nil {
            try await Task.sleep(for: .milliseconds(100))
            seen = monitor.items.first
        }
        #expect(seen?.name == "big.zip")
        #expect(seen?.total == 1_000)
        #expect(seen?.completed == 250)

        progress.unpublish()
        for _ in 0..<30 where !monitor.items.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(monitor.items.isEmpty, "a finished download leaves the notch")
    }
}

@Suite("Coding assistant requests")
struct AgentRequestTests {
    private func hookInput(_ tool: String, _ input: [String: Any], cwd: String = "/Users/me/app") -> Data {
        try! JSONSerialization.data(withJSONObject: [
            "session_id": "s", "cwd": cwd, "hook_event_name": "PermissionRequest",
            "tool_name": tool, "tool_input": input,
        ])
    }

    @Test func describesToolCalls() {
        let bash = AgentRequest(claudeHookInput: hookInput("Bash", ["command": "npm test\n"]))
        #expect(bash?.title == "Run a command")
        #expect(bash?.detail == "npm test")
        #expect(bash?.project == "app")
        #expect(bash?.agent == "Claude Code")

        let edit = AgentRequest(claudeHookInput: hookInput("Edit", ["file_path": "/Users/me/app/src/main.swift"]))
        #expect(edit?.title == "Edit a file")
        #expect(edit?.detail == "src/main.swift", "paths inside the project are shortened")

        let outside = AgentRequest(claudeHookInput: hookInput("Write", ["file_path": "/etc/hosts"]))
        #expect(outside?.detail == "/etc/hosts")

        let mcp = AgentRequest(claudeHookInput: hookInput("mcp__github__create_issue", [:]))
        #expect(mcp?.title == "Use a connected tool")
        #expect(mcp?.detail == "github create issue")

        let long = AgentRequest(claudeHookInput: hookInput("Bash", ["command": String(repeating: "x", count: 5_000)]))
        #expect(long?.detail.count == AgentRequest.maximumDetail)
    }

    @Test func ignoresOtherInput() {
        #expect(AgentRequest(claudeHookInput: Data("nope".utf8)) == nil)
        let other = try! JSONSerialization.data(withJSONObject: ["hook_event_name": "Stop", "tool_name": "Bash"])
        #expect(AgentRequest(claudeHookInput: other) == nil)
    }

    @Test func hookOutputMatchesClaudeCode() throws {
        #expect(AgentDecision.ask.claudeHookOutput.isEmpty, "no output leaves Claude Code's own prompt")
        let allow = try #require(JSONSerialization.jsonObject(with: AgentDecision.allow.claudeHookOutput) as? [String: Any])
        let output = try #require(allow["hookSpecificOutput"] as? [String: Any])
        #expect(output["hookEventName"] as? String == "PermissionRequest")
        #expect((output["decision"] as? [String: Any])?["behavior"] as? String == "allow")
        let deny = try #require(JSONSerialization.jsonObject(with: AgentDecision.deny.claudeHookOutput) as? [String: Any])
        let denyDecision = (deny["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
        #expect(denyDecision?["behavior"] as? String == "deny")
        #expect(denyDecision?["message"] != nil)
    }
}

@Suite("Claude Code settings")
struct ClaudeHookSettingsTests {
    private func temporaryFile(_ contents: String?) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("claude-\(UUID().uuidString)/settings.json")
        if let contents {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(contents.utf8).write(to: url)
        }
        return url
    }

    private func read(_ url: URL) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
    }

    @Test func installsBesideOtherSettingsAndRemovesCleanly() throws {
        let url = temporaryFile("""
        {"model": "opus", "hooks": {"PermissionRequest": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "mine.sh"}]}],
                                     "Stop": [{"hooks": [{"type": "command", "command": "say done"}]}]}}
        """)
        let command = ClaudeHookSettings.command(executable: "/Applications/Dynamic Ledge.app/Contents/MacOS/DynamicNotch", socket: "/tmp/a b.sock")
        #expect(command == "'/Applications/Dynamic Ledge.app/Contents/MacOS/DynamicNotch' --agent-hook '/tmp/a b.sock'")

        try ClaudeHookSettings.install(command: command, at: url)
        #expect(ClaudeHookSettings.isInstalled(at: url))
        #expect(ClaudeHookSettings.isCurrent(command: command, at: url))
        var settings = read(url)
        #expect(settings["model"] as? String == "opus")
        var groups = (settings["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]]
        #expect(groups?.count == 2, "the user's own hook stays")

        // Installing again (say after the app moved) replaces ours instead of adding a second.
        try ClaudeHookSettings.install(command: command.replacingOccurrences(of: "Applications", with: "Apps"), at: url)
        groups = (read(url)["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]]
        #expect(groups?.count == 2)
        #expect(!ClaudeHookSettings.isCurrent(command: command, at: url))

        try ClaudeHookSettings.uninstall(at: url)
        settings = read(url)
        #expect(!ClaudeHookSettings.isInstalled(at: url))
        groups = (settings["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]]
        #expect(groups?.count == 1)
        #expect((settings["hooks"] as? [String: Any])?["Stop"] != nil)
    }

    @Test func createsTheFileAndTidiesUp() throws {
        let url = temporaryFile(nil)
        try ClaudeHookSettings.install(command: "'x' --agent-hook 's'", at: url)
        #expect(ClaudeHookSettings.isInstalled(at: url))
        try ClaudeHookSettings.uninstall(at: url)
        #expect(read(url).isEmpty, "nothing of ours is left behind")
    }

    @Test func leavesABrokenFileAlone() {
        let url = temporaryFile("{ this isn't json")
        #expect(throws: ClaudeHookSettings.Failure.unreadable) {
            try ClaudeHookSettings.install(command: "'x' --agent-hook 's'", at: url)
        }
        #expect((try? String(contentsOf: url, encoding: .utf8)) == "{ this isn't json")
    }
}

@MainActor
@Suite("Coding assistant round trip")
struct AgentBridgeTests {
    private func socketPath() -> String {
        // Short, since socket paths are limited to 104 bytes.
        "/tmp/dl-\(UUID().uuidString.prefix(8)).sock"
    }

    private let input = try! JSONSerialization.data(withJSONObject: [
        "cwd": "/Users/me/app", "hook_event_name": "PermissionRequest",
        "tool_name": "Bash", "tool_input": ["command": "ls"],
    ])

    private func ask(_ path: String) -> Task<Data, Never> {
        let input = input
        return Task.detached { AgentHookClient.answer(input: input, socket: path) }
    }

    private func waitForPending(_ bridge: AgentBridge, count: Int = 1) async throws {
        for _ in 0..<50 where bridge.pending.count < count {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func allowAndDenyReachTheHook() async throws {
        let path = socketPath()
        let bridge = AgentBridge(socketPath: path)
        bridge.start()
        defer { bridge.stop() }
        #expect(bridge.isRunning)
        #expect((try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int) == 0o600)

        let first = ask(path)
        try await waitForPending(bridge)
        #expect(bridge.pending.first?.detail == "ls")
        bridge.answer(bridge.pending[0].id, .allow)
        #expect(await first.value == AgentDecision.allow.claudeHookOutput)

        let second = ask(path)
        try await waitForPending(bridge)
        bridge.answer(bridge.pending[0].id, .deny)
        #expect(await second.value == AgentDecision.deny.claudeHookOutput)

        let third = ask(path)
        try await waitForPending(bridge)
        bridge.answer(bridge.pending[0].id, .ask)
        #expect(await third.value.isEmpty)
        #expect(bridge.pending.isEmpty)
    }

    @Test func requestsWaitTheirTurn() async throws {
        let path = socketPath()
        let bridge = AgentBridge(socketPath: path)
        bridge.start()
        defer { bridge.stop() }
        let one = ask(path)
        try await waitForPending(bridge)
        let two = ask(path)
        try await waitForPending(bridge, count: 2)
        #expect(bridge.pending.count == 2)
        bridge.answer(bridge.pending[0].id, .allow)
        bridge.answer(bridge.pending[0].id, .deny)
        #expect(await one.value == AgentDecision.allow.claudeHookOutput)
        #expect(await two.value == AgentDecision.deny.claudeHookOutput)
    }

    @Test func noAppMeansNoAnswer() {
        #expect(AgentHookClient.answer(input: input, socket: socketPath()).isEmpty, "Claude Code falls back to its own prompt")
        #expect(AgentHookClient.answer(input: Data(), socket: socketPath()).isEmpty)
    }

    @Test func stoppingSendsWaitingRequestsBack() async throws {
        let path = socketPath()
        let bridge = AgentBridge(socketPath: path)
        bridge.start()
        let waiting = ask(path)
        try await waitForPending(bridge)
        bridge.stop()
        #expect(await waiting.value.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: path))
    }
}

@MainActor
@Suite("Coding assistant alert")
struct AgentAlertTests {
    @Test func showsOneRequestAtATimeAndClosingAsksInTerminal() async throws {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.agentApprovalsEnabled = true
        let model = IslandModel(
            settings: settings,
            tray: TrayStore(folder: nil),
            clipboard: ClipboardMonitor(pasteboard: NSPasteboard(name: NSPasteboard.Name("NotchTests-\(UUID().uuidString)"))),
            notes: NotesStore(defaults: defaults)
        )
        let first = AgentRequest(agent: "Claude Code", project: "app", toolName: "Bash", title: "Run a command", detail: "ls")
        let alert = IslandAlert.agentRequest(first)
        #expect(alert.isUrgent)
        #expect(alert.usesExpandedLayout)
        model.receive(alert)
        #expect(model.alerts.current == alert)
        model.tapPill()
        #expect(model.alerts.current == alert, "a stray click doesn't answer it")
    }
}
