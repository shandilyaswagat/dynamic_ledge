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
        #expect(long?.detail.count == 5_000)
    }

    @Test func preservesCompleteApprovalDetails() throws {
        let command = String(repeating: "echo safe; ", count: 100) + "echo last-command"
        let request = try #require(AgentRequest(claudeHookInput: hookInput("Bash", ["command": command])))
        #expect(request.reviewDetail == command)
        #expect(request.reviewLineCount(charactersPerLine: 60) == IslandMetrics.ContentHeight.agentRequestLines)
        let multiline = try #require(AgentRequest(claudeHookInput: hookInput("Bash", ["command": "ls\npwd\nwhoami"])))
        #expect(multiline.reviewLineCount(charactersPerLine: 60) == 3)
        let short = try #require(AgentRequest(claudeHookInput: hookInput("Bash", ["command": "ls"])))
        #expect(short.reviewLineCount(charactersPerLine: 60) == 1)
        let edit = try #require(AgentRequest(claudeHookInput: hookInput("Edit", ["file_path": "/a", "old_string": "before", "new_string": "after"])))
        #expect(edit.reviewDetail.contains("before"))
        #expect(edit.reviewDetail.contains("after"))
        let patch = "*** Begin Patch\n*** Update File: a\n-dangerous\n+safe\n*** End Patch"
        let change = try #require(AgentRequest(claudeHookInput: hookInput("apply_patch", ["command": patch])))
        let arguments = try #require(JSONSerialization.jsonObject(with: Data(change.reviewDetail.utf8)) as? [String: String])
        #expect(arguments["command"] == patch)
    }

    @Test func makesHiddenCommandControlsVisible() {
        let request = AgentRequest(project: "app", toolName: "Bash", title: "Run a command", detail: "echo a\r\u{202e}hidden")
        #expect(request.visibleReviewDetail == "echo a\\u{d}\\u{202e}hidden")
    }

    @Test func longApprovalGrowsOnlyAsTallAsItNeeds() {
        let engine = LayoutEngine(screen: .sample, appearance: .standard)
        let short = AgentRequest(project: "app", toolName: "Bash", title: "Run a command", detail: "ls")
        func layout(_ text: String) -> IslandLayout {
            var request = short
            request.reviewDetail = text
            return engine.layout(for: .alert(.agentRequest(request)), homeHasMedia: false, hovering: false)
        }
        let normal = layout("ls")
        let twoLines = layout(String(repeating: "x", count: engine.agentCharactersPerLine + 5))
        let fourLines = layout("a\nb\nc\nd")
        let huge = layout(String(repeating: "command ", count: 1_000))
        #expect(twoLines == normal, "two lines fit the usual panel")
        #expect(fourLines.content.height > normal.content.height)
        #expect(huge.content.height > fourLines.content.height)
        #expect(huge.content.width == normal.content.width, "never wider than usual")
        #expect(huge.pill.maxY <= engine.windowSize.height)
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
        let command = AgentHookSettings.command(executable: "/Applications/Dynamic Ledge.app/Contents/MacOS/DynamicNotch", socket: "/tmp/a b.sock", kind: .claude)
        #expect(command == "'/Applications/Dynamic Ledge.app/Contents/MacOS/DynamicNotch' --agent-hook '/tmp/a b.sock'")

        try AgentHookSettings.install(.claude, command: command, at: url)
        #expect(AgentHookSettings.isInstalled(.claude, at: url))
        #expect(AgentHookSettings.isCurrent(.claude, command: command, at: url))
        var settings = read(url)
        #expect(settings["model"] as? String == "opus")
        var groups = (settings["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]]
        #expect(groups?.count == 2, "the user's own hook stays")

        // Installing again (say after the app moved) replaces ours instead of adding a second.
        try AgentHookSettings.install(.claude, command: command.replacingOccurrences(of: "Applications", with: "Apps"), at: url)
        groups = (read(url)["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]]
        #expect(groups?.count == 2)
        #expect(!AgentHookSettings.isCurrent(.claude, command: command, at: url))

        try AgentHookSettings.uninstall(.claude, at: url)
        settings = read(url)
        #expect(!AgentHookSettings.isInstalled(.claude, at: url))
        groups = (settings["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]]
        #expect(groups?.count == 1)
        #expect((settings["hooks"] as? [String: Any])?["Stop"] != nil)
    }

    @Test func createsTheFileAndTidiesUp() throws {
        let url = temporaryFile(nil)
        try AgentHookSettings.install(.claude, command: "'x' --agent-hook 's'", at: url)
        #expect(AgentHookSettings.isInstalled(.claude, at: url))
        try AgentHookSettings.uninstall(.claude, at: url)
        #expect(read(url).isEmpty, "nothing of ours is left behind")
    }

    @Test func leavesABrokenFileAlone() {
        let url = temporaryFile("{ this isn't json")
        #expect(throws: AgentHookSettings.Failure.unreadable) {
            try AgentHookSettings.install(.claude, command: "'x' --agent-hook 's'", at: url)
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
        settings.agentApprovals = [.claude]
        let model = IslandModel(
            settings: settings,
            tray: TrayStore(folder: nil),
            clipboard: ClipboardMonitor(pasteboard: NSPasteboard(name: NSPasteboard.Name("NotchTests-\(UUID().uuidString)"))),
            notes: NotesStore(defaults: defaults)
        )
        let first = AgentRequest(kind: .claude, project: "app", toolName: "Bash", title: "Run a command", detail: "ls")
        let alert = IslandAlert.agentRequest(first)
        #expect(alert.isUrgent)
        #expect(alert.usesExpandedLayout)
        model.receive(alert)
        #expect(model.alerts.current == alert)
        model.tapPill()
        #expect(model.alerts.current == alert, "a stray click doesn't answer it")
    }
}

@Suite("Claude Code settings through a link")
struct ClaudeHookSymlinkTests {
    @Test func writesThroughALinkAndKeepsPermissions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dotfiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let real = folder.appendingPathComponent("claude-settings.json")
        try Data(#"{"model": "opus"}"#.utf8).write(to: real)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: real.path)
        let link = folder.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        try AgentHookSettings.install(.claude, command: "'x' --agent-hook 's'", at: link)
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == real.path, "still a link")
        #expect(AgentHookSettings.isInstalled(.claude, at: real))
        #expect((try? FileManager.default.attributesOfItem(atPath: real.path)[.posixPermissions] as? Int) == 0o600)
    }
}

@Suite("Every coding assistant")
struct AgentKindsTests {
    private func json(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }
    private func decode(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:] }

    @Test func readsEachAssistantsInput() {
        let codex = AgentRequest(hookInput: json([
            "hook_event_name": "PermissionRequest", "tool_name": "apply_patch", "cwd": "/w/site",
            "tool_input": ["command": "*** Begin Patch\n*** Update File: src/a.ts\n*** Add File: b.ts\n*** End Patch"],
        ]), kind: .codex)
        #expect(codex?.agent == "Codex")
        #expect(codex?.title == "Edit files")
        #expect(codex?.detail == "src/a.ts, b.ts")
        #expect(codex?.project == "site")

        let antigravity = AgentRequest(hookInput: json([
            "toolCall": ["name": "run_command", "args": ["CommandLine": "npm run build"]],
            "workspacePaths": ["/w/app"], "conversationId": "c",
        ]), kind: .antigravity)
        #expect(antigravity?.title == "Run a command")
        #expect(antigravity?.detail == "npm run build")
        #expect(antigravity?.project == "app")
        #expect(AgentRequest(hookInput: json(["toolCall": ["name": "view_file", "args": [:]]]), kind: .antigravity) == nil)

        let cursor = AgentRequest(hookInput: json([
            "hook_event_name": "beforeShellExecution", "command": "git push", "cwd": "", "workspace_roots": ["/w/repo"],
        ]), kind: .cursor)
        #expect(cursor?.detail == "git push")
        #expect(cursor?.project == "repo", "an empty cwd falls back to the workspace")

        let copilot = AgentRequest(hookInput: json(["toolName": "shell", "toolArgs": "{\"command\":\"ls -la\"}", "cwd": "/w/x"]), kind: .copilot)
        #expect(copilot?.title == "Run a command")
        #expect(copilot?.detail == "ls -la")
    }

    @Test func answersInEachAssistantsFormat() {
        #expect(AgentKind.codex.output(for: .allow) == AgentKind.claude.output(for: .allow), "Codex shares Claude Code's format")
        #expect(AgentKind.codex.output(for: .ask).isEmpty)
        #expect(decode(AgentKind.antigravity.output(for: .allow))["decision"] as? String == "allow")
        #expect(decode(AgentKind.antigravity.output(for: .deny))["reason"] != nil)
        #expect(decode(AgentKind.antigravity.fallbackOutput)["decision"] as? String == "ask", "never a failure, which would block the command")
        #expect(decode(AgentKind.cursor.output(for: .deny))["permission"] as? String == "deny")
        #expect(decode(AgentKind.cursor.fallbackOutput)["permission"] as? String == "ask")
        #expect(decode(AgentKind.copilot.output(for: .allow))["behavior"] as? String == "allow")
        #expect(AgentKind.copilot.fallbackOutput.isEmpty)
    }

    @Test func hookCommandNamesTheAssistant() {
        #expect(!AgentHookSettings.command(executable: "/a", socket: "/s", kind: .claude).contains("--agent "), "Claude Code's hook stays as before")
        #expect(AgentHookSettings.command(executable: "/a", socket: "/s", kind: .cursor).hasSuffix("--agent cursor"))
    }

    private func temporaryFile(_ contents: String?) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agents-\(UUID().uuidString)/hooks.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let contents { try? Data(contents.utf8).write(to: url) }
        return url
    }

    @Test func installsInEachFormat() throws {
        for kind in AgentKind.allCases {
            let url = temporaryFile(nil)
            let command = AgentHookSettings.command(executable: "/App", socket: "/s", kind: kind)
            try AgentHookSettings.install(kind, command: command, at: url)
            try AgentHookSettings.install(kind, command: command, at: url)
            #expect(AgentHookSettings.isCurrent(kind, command: command, at: url), "\(kind)")
            let hooks = decode(try Data(contentsOf: url))["hooks"] as? [String: Any] ?? [:]
            #expect(hooks.count == 1, "\(kind)")
            #expect((hooks.values.first as? [Any])?.count == 1, "installing twice keeps one hook for \(kind)")
            try AgentHookSettings.uninstall(kind, at: url)
            #expect(!AgentHookSettings.isInstalled(kind, at: url), "\(kind)")
        }
    }

    @Test func cursorKeepsOtherHooks() throws {
        let url = temporaryFile(#"{"version": 1, "hooks": {"beforeShellExecution": [{"command": "./audit.sh"}], "afterFileEdit": [{"command": "./fmt.sh"}]}}"#)
        try AgentHookSettings.install(.cursor, command: "'x' --agent-hook 's' --agent cursor", at: url)
        var hooks = decode(try Data(contentsOf: url))["hooks"] as? [String: Any] ?? [:]
        #expect((hooks["beforeShellExecution"] as? [Any])?.count == 2)
        try AgentHookSettings.uninstall(.cursor, at: url)
        let settings = decode(try Data(contentsOf: url))
        hooks = settings["hooks"] as? [String: Any] ?? [:]
        #expect((hooks["beforeShellExecution"] as? [[String: Any]])?.first?["command"] as? String == "./audit.sh")
        #expect(hooks["afterFileEdit"] != nil)
        #expect(settings["version"] as? Int == 1)
    }

    @Test func copilotsOwnFileIsRemoved() throws {
        let url = temporaryFile(nil)
        try AgentHookSettings.install(.copilot, command: "'x' --agent-hook 's' --agent copilot", at: url)
        let entry = ((decode(try Data(contentsOf: url))["hooks"] as? [String: Any])?["permissionRequest"] as? [[String: Any]])?.first
        #expect(entry?["bash"] as? String == "'x' --agent-hook 's' --agent copilot")
        #expect(entry?["timeoutSec"] as? Int == AgentHookSettings.timeout)
        try AgentHookSettings.uninstall(.copilot, at: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    @Test func settingsCarryOverTheOldClaudeSwitch() {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        defaults.set(true, forKey: "activity.agentApprovals")
        #expect(SettingsStore(defaults: defaults).agentApprovals == [.claude])
        let settings = SettingsStore(defaults: defaults)
        settings.agentApprovals = [.codex, .cursor]
        #expect(SettingsStore(defaults: defaults).agentApprovals == [.codex, .cursor])
    }
}

@MainActor
@Suite("Every assistant round trip")
struct AgentKindsBridgeTests {
    @Test func eachAssistantGetsItsOwnAnswer() async throws {
        let path = "/tmp/dl-\(UUID().uuidString.prefix(8)).sock"
        let bridge = AgentBridge(socketPath: path)
        bridge.start()
        defer { bridge.stop() }
        let inputs: [AgentKind: [String: Any]] = [
            .codex: ["hook_event_name": "PermissionRequest", "tool_name": "Bash", "tool_input": ["command": "ls"], "cwd": "/w"],
            .antigravity: ["toolCall": ["name": "run_command", "args": ["CommandLine": "ls"]], "workspacePaths": ["/w"]],
            .cursor: ["hook_event_name": "beforeShellExecution", "command": "ls", "cwd": "/w"],
            .copilot: ["toolName": "bash", "toolArgs": ["command": "ls"], "cwd": "/w"],
        ]
        for (kind, object) in inputs {
            let input = try JSONSerialization.data(withJSONObject: object)
            let reply = Task.detached { AgentHookClient.answer(input: input, socket: path, kind: kind) }
            for _ in 0..<50 where bridge.pending.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
            #expect(bridge.pending.first?.kind == kind)
            bridge.answer(bridge.pending[0].id, .allow)
            #expect(await reply.value == kind.output(for: .allow), "\(kind)")
        }

        // Switched off: sent straight back to ask as usual.
        bridge.enabledKinds = [.claude]
        let input = try JSONSerialization.data(withJSONObject: inputs[.cursor]!)
        let reply = await Task.detached { AgentHookClient.answer(input: input, socket: path, kind: .cursor) }.value
        #expect(reply == AgentKind.cursor.fallbackOutput)
        #expect(bridge.pending.isEmpty)
    }

    @Test func noAppMeansAskForEveryAssistant() {
        let input = Data(#"{"command":"ls"}"#.utf8)
        for kind in AgentKind.allCases {
            #expect(AgentHookClient.answer(input: input, socket: "/tmp/none-\(UUID().uuidString.prefix(6)).sock", kind: kind) == kind.fallbackOutput)
        }
    }
}

@Suite("Agent socket authentication")
struct AgentSocketAuthenticationTests {
    @Test func rejectsInvalidConnection() {
        #expect(!AgentHookClient.trustsPeer(-1))
    }

    @Test func rejectsImpersonatingServer() async throws {
        let path = "/tmp/ledge-auth-\(UUID().uuidString.prefix(8)).sock"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", """
        import socket, sys
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(sys.argv[1])
        server.listen(1)
        connection, _ = server.accept()
        try:
            connection.sendall(b'{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}\\n')
        except OSError:
            pass
        connection.close()
        server.close()
        """, path]
        try process.run()
        defer {
            if process.isRunning { process.terminate() }
            try? FileManager.default.removeItem(atPath: path)
        }
        for _ in 0..<150 {
            if FileManager.default.fileExists(atPath: path) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(FileManager.default.fileExists(atPath: path))
        let input = Data(#"{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"echo test"}}"#.utf8)
        let reply = await Task.detached { AgentHookClient.answer(input: input, socket: path) }.value
        #expect(reply == AgentKind.claude.fallbackOutput)
    }
}
