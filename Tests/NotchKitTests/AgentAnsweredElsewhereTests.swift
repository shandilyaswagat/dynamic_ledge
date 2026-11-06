import AppKit
import Foundation
import Testing
@testable import NotchKit

private func json(_ object: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: object) }

private func line(_ object: [String: Any]) -> Data { json(object) + Data([0x0A]) }

private func call(_ id: String, _ command: String) -> Data {
    line(["type": "assistant", "message": ["content": [["type": "tool_use", "id": id, "name": "Bash", "input": ["command": command]]]]])
}

private func result(_ id: String) -> Data {
    line(["type": "user", "message": ["content": [["type": "tool_result", "tool_use_id": id, "content": "ok"]]]])
}

@Suite("Answered in the assistant's window")
struct AgentTranscriptScanTests {
    @Test func questionsAndPlansStayInTheAssistant() {
        for tool in ["AskUserQuestion", "ExitPlanMode"] {
            let input = json(["hook_event_name": "PermissionRequest", "tool_name": tool, "tool_input": [:] as [String: Any], "cwd": "/w/app"])
            #expect(AgentRequest(hookInput: input, kind: .claude) == nil, "\(tool)")
        }
        let bash = json(["hook_event_name": "PermissionRequest", "tool_name": "Bash", "tool_input": ["command": "ls"], "cwd": "/w/app"])
        #expect(AgentRequest(hookInput: bash, kind: .claude) != nil)
    }

    @Test func waitsForTheResultOfTheNewestMatchingCall() {
        var scan = AgentTranscriptScan(toolName: "Bash", toolInput: ["command": "ls"])
        // An earlier run of the same command and its result, then something else.
        let earlier = [call("a", "ls"), result("a"), call("b", "pwd"), result("b")].map { scan.consume($0) }
        #expect(earlier == [false, true, false, false], "the first read only learns what's there")
        // The call being asked about.
        let asked = scan.consume(call("c", "ls"))
        #expect(!asked)
        #expect(scan.waitingCall == "c")
        let noise = scan.consume(Data(#"{"type":"progress"}"#.utf8))
        #expect(!noise)
        let answered = scan.consume(result("c"))
        #expect(answered, "answered in Claude Code")
    }

    @Test func otherCallsFinishingDontCount() {
        var scan = AgentTranscriptScan(toolName: "Bash", toolInput: ["command": "ls"])
        _ = scan.consume(call("x", "npm test"))
        _ = scan.consume(call("c", "ls"))
        let other = scan.consume(result("x"))
        #expect(!other, "a parallel call finishing isn't this answer")
        let answered = scan.consume(result("c"))
        #expect(answered)
    }
}

@MainActor
@Suite("Answered in the assistant's window, end to end")
struct AgentAnsweredElsewhereTests {
    private func socketPath() -> String { "/tmp/dl-\(UUID().uuidString.prefix(8)).sock" }

    private func transcript(_ lines: Data...) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("transcript-\(UUID().uuidString).jsonl")
        try lines.reduce(Data(), +).write(to: url)
        return url
    }

    private func append(_ data: Data, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()
    }

    private func input(transcript: URL, tool: String = "Bash") -> Data {
        json(["hook_event_name": "PermissionRequest", "tool_name": tool, "tool_input": ["command": "ls"],
              "cwd": "/w/app", "transcript_path": transcript.path])
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<60 where !condition() {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func aResultInTheTranscriptClosesTheRequest() async throws {
        let url = try transcript(call("old", "ls"), result("old"), call("now", "ls"))
        defer { try? FileManager.default.removeItem(at: url) }
        let path = socketPath()
        let bridge = AgentBridge(socketPath: path)
        bridge.start()
        defer { bridge.stop() }
        let data = input(transcript: url)
        let hook = Task.detached { AgentHookClient.answer(input: data, socket: path) }
        try await waitUntil { bridge.pending.count == 1 }
        #expect(bridge.pending.count == 1)
        try await Task.sleep(for: .milliseconds(700))
        #expect(bridge.pending.count == 1, "the earlier run's result doesn't count")

        try append(result("now"), to: url)
        try await waitUntil { bridge.pending.isEmpty }
        #expect(bridge.pending.isEmpty, "answered in Claude Code, so the notch lets it go")
        #expect(await hook.value.isEmpty)
    }

    @Test func questionsNeverReachTheNotch() async throws {
        let url = try transcript()
        defer { try? FileManager.default.removeItem(at: url) }
        let path = socketPath()
        let bridge = AgentBridge(socketPath: path)
        bridge.start()
        defer { bridge.stop() }
        let data = input(transcript: url, tool: "AskUserQuestion")
        let reply = await Task.detached { AgentHookClient.answer(input: data, socket: path) }.value
        #expect(reply.isEmpty, "Claude Code asks it in its own window")
        #expect(bridge.pending.isEmpty)
    }

    @Test func homeLeavesTheRequestWaitingAndItComesBack() async throws {
        let defaults = UserDefaults(suiteName: "NotchTests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.agentApprovals = [.claude]
        let model = IslandModel(
            settings: settings,
            tray: TrayStore(folder: nil),
            clipboard: ClipboardMonitor(pasteboard: NSPasteboard(name: NSPasteboard.Name("NotchTests-\(UUID().uuidString)"))),
            notes: NotesStore(defaults: defaults)
        )
        model.agents.start()
        defer { model.agents.stop() }
        let path = model.agents.socketPath
        let data = json(["hook_event_name": "PermissionRequest", "tool_name": "Bash", "tool_input": ["command": "ls"], "cwd": "/w/app"])
        let hook = Task.detached { AgentHookClient.answer(input: data, socket: path) }
        try await waitUntil { model.agents.pending.count == 1 }
        guard case .agentRequest(let shown)? = model.alerts.current else {
            Issue.record("the request should show")
            return
        }

        model.setAsideAgentRequest()
        #expect(model.alerts.current == nil)
        #expect(model.expandTarget == .home)
        #expect(model.agents.pending.map(\.id) == [shown.id], "still waiting, unanswered")

        model.collapse()
        #expect(model.alerts.current == .agentRequest(shown), "back once Home closes")
        model.answerAgent(.allow)
        #expect(await hook.value == AgentDecision.allow.claudeHookOutput)
    }
}
