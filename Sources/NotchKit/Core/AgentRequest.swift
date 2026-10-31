import Foundation

/// The coding assistants whose permission requests the notch can answer. Each has its own hook
/// format; the app adds a hook only for the ones switched on in Settings.
public enum AgentKind: String, CaseIterable, Sendable, Codable, Identifiable {
    case claude
    case codex
    case copilot
    case antigravity
    case cursor

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .copilot: "Copilot CLI"
        case .antigravity: "Antigravity"
        case .cursor: "Cursor"
        }
    }

    /// True when the tool asks the hook only for actions that need your OK. The others ask
    /// before every terminal command, so the notch does too.
    public var asksOnlyWhenNeeded: Bool {
        switch self {
        case .claude, .codex, .copilot: true
        case .antigravity, .cursor: false
        }
    }

    /// What the hook prints when the notch gives no answer (the app isn't running, or the person
    /// closed it): the tool's own prompt, as if there were no hook. Antigravity blocks a command
    /// whose hook fails, so it's told to ask instead.
    public var fallbackOutput: Data {
        output(for: .ask)
    }

    /// The hook's answer in the tool's own format.
    public func output(for decision: AgentDecision) -> Data {
        let reason = "Denied from Dynamic Ledge."
        let object: [String: Any]
        switch (self, decision) {
        case (.claude, .ask), (.codex, .ask), (.copilot, .ask):
            return Data()
        case (.claude, _), (.codex, _):
            var answer: [String: Any] = ["behavior": decision == .allow ? "allow" : "deny"]
            if decision == .deny { answer["message"] = reason }
            object = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": answer]]
        case (.copilot, _):
            object = decision == .allow ? ["behavior": "allow"] : ["behavior": "deny", "message": reason]
        case (.antigravity, _):
            object = decision == .deny ? ["decision": "deny", "reason": reason] : ["decision": decision.rawValue]
        case (.cursor, _):
            var answer: [String: Any] = ["permission": decision.rawValue]
            if decision == .deny {
                answer["userMessage"] = reason
                answer["agentMessage"] = "The user denied this command."
            }
            object = answer
        }
        return (try? JSONSerialization.data(withJSONObject: object, options: .sortedKeys)) ?? Data()
    }
}

/// A coding assistant asking whether it may do something, answered from the notch.
public struct AgentRequest: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var kind: AgentKind
    /// The folder the assistant is working in, by name.
    public var project: String
    public var toolName: String
    /// What the assistant wants to do, in one short line ("Run a command").
    public var title: String
    /// The command, file or address it applies to.
    public var detail: String

    /// "Claude Code", "Codex" and so on.
    public var agent: String { kind.displayName }

    public init(id: UUID = UUID(), kind: AgentKind = .claude, project: String, toolName: String, title: String, detail: String) {
        self.id = id
        self.kind = kind
        self.project = project
        self.toolName = toolName
        self.title = title
        self.detail = detail
    }

    /// The longest detail kept; the notch shows two lines of it.
    static let maximumDetail = 600

    /// Reads what a tool's hook was given. Nil when it isn't something to ask about.
    public init?(hookInput data: Data, kind: AgentKind, id: UUID = UUID()) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let parsed: (tool: String, input: [String: Any], cwd: String)?
        switch kind {
        case .claude, .codex:
            // Claude Code's and Codex's PermissionRequest share a format.
            if object["hook_event_name"] as? String == "PermissionRequest", let tool = object["tool_name"] as? String, !tool.isEmpty {
                parsed = (tool, object["tool_input"] as? [String: Any] ?? [:], object["cwd"] as? String ?? "")
            } else {
                parsed = nil
            }
        case .copilot:
            // camelCase from the CLI's own events, snake_case from its Claude-style ones.
            let tool = object["toolName"] as? String ?? object["tool_name"] as? String ?? ""
            let arguments = object["toolArgs"] ?? object["tool_input"]
            let input = (arguments as? [String: Any])
                ?? (arguments as? String).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                ?? [:]
            parsed = tool.isEmpty ? nil : (Self.claudeName(forCopilot: tool), input, object["cwd"] as? String ?? "")
        case .antigravity:
            let call = object["toolCall"] as? [String: Any] ?? [:]
            let arguments = call["args"] as? [String: Any] ?? [:]
            let folder = (object["workspacePaths"] as? [String])?.first ?? ""
            if call["name"] as? String == "run_command" {
                parsed = ("Bash", ["command": arguments["CommandLine"] as? String ?? arguments["command"] as? String ?? ""], folder)
            } else {
                parsed = nil
            }
        case .cursor:
            let folder = (object["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (object["workspace_roots"] as? [String])?.first ?? ""
            if let command = object["command"] as? String {
                parsed = ("Bash", ["command": command], folder)
            } else {
                parsed = nil
            }
        }
        guard let parsed else { return nil }
        let (title, detail) = Self.describe(tool: parsed.tool, input: parsed.input, cwd: parsed.cwd)
        self.init(
            id: id,
            kind: kind,
            project: parsed.cwd.isEmpty ? "" : URL(fileURLWithPath: parsed.cwd).lastPathComponent,
            toolName: parsed.tool,
            title: title,
            detail: String(detail.prefix(Self.maximumDetail))
        )
    }

    /// Kept for hooks written by earlier builds, which only handled Claude Code.
    public init?(claudeHookInput data: Data, id: UUID = UUID()) {
        self.init(hookInput: data, kind: .claude, id: id)
    }

    /// Copilot's tool names, mapped to the descriptions shared by every assistant.
    static func claudeName(forCopilot tool: String) -> String {
        switch tool.lowercased() {
        case "bash", "shell", "powershell": "Bash"
        case "edit", "str_replace_editor": "Edit"
        case "create", "write": "Write"
        case "view", "read": "Read"
        default: tool
        }
    }

    /// A plain description of a tool call: what it does, and on what.
    static func describe(tool: String, input: [String: Any], cwd: String) -> (String, String) {
        func string(_ key: String) -> String { (input[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        func path(_ key: String) -> String {
            let value = string(key)
            // Inside the project, the relative path is shorter and just as clear.
            if !cwd.isEmpty, value.hasPrefix(cwd + "/") { return String(value.dropFirst(cwd.count + 1)) }
            return value
        }
        switch tool {
        case "Bash":
            return ("Run a command", string("command"))
        case "Edit", "MultiEdit":
            return ("Edit a file", path("file_path").isEmpty ? path("path") : path("file_path"))
        case "Write":
            return ("Write a file", path("file_path").isEmpty ? path("path") : path("file_path"))
        case "apply_patch":
            // Codex: the patch names the files it touches ("*** Update File: src/a.swift").
            let files = string("command").split(separator: "\n").compactMap { line -> String? in
                for prefix in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] where line.hasPrefix(prefix) {
                    return String(line.dropFirst(prefix.count))
                }
                return nil
            }
            return ("Edit files", files.isEmpty ? string("command") : files.joined(separator: ", "))
        case "NotebookEdit":
            return ("Edit a notebook", path("notebook_path"))
        case "Read":
            return ("Read a file", path("file_path").isEmpty ? path("path") : path("file_path"))
        case "WebFetch":
            return ("Open a web page", string("url"))
        case "WebSearch":
            return ("Search the web", string("query"))
        default:
            if tool.hasPrefix("mcp__") {
                // mcp__server__tool → "server: tool".
                let parts = tool.split(separator: "_", omittingEmptySubsequences: true).dropFirst()
                return ("Use a connected tool", parts.joined(separator: " "))
            }
            let summary = input.keys.sorted().first.map { "\($0): \(input[$0].map { "\($0)" } ?? "")" } ?? ""
            return ("Use \(tool)", summary)
        }
    }
}

/// The answer sent back to the assistant.
public enum AgentDecision: String, Sendable {
    case allow
    case deny
    /// No answer from the notch: the assistant asks in its own window as usual.
    case ask

    /// Claude Code's format, kept for callers and tests from before other assistants.
    public var claudeHookOutput: Data { AgentKind.claude.output(for: self) }
}

/// Adds or removes Dynamic Ledge's hook in an assistant's own settings file, leaving everything
/// else in the file as it was.
public enum AgentHookSettings {
    /// Marks our hook, so it's found again whatever path the app is at.
    public static let flag = "--agent-hook"
    public static let agentFlag = "--agent"
    /// Seconds the assistant waits for an answer before asking in its own window.
    public static let timeout = 120

    public enum Failure: Error, Equatable {
        /// The file exists but isn't a JSON object; it's left untouched.
        case unreadable
        case unwritable
    }

    /// How a tool lists its hooks.
    enum Layout {
        /// `hooks.<event>: [{matcher, hooks: [{type, command, timeout}]}]` (Claude Code, Codex, Antigravity).
        case grouped(event: String, matcher: String)
        /// `version: 1, hooks.<event>: [{...entry}]` (Cursor, Copilot CLI).
        case flat(event: String, entry: (String) -> [String: Any])
    }

    static func layout(for kind: AgentKind) -> Layout {
        switch kind {
        case .claude, .codex: .grouped(event: "PermissionRequest", matcher: "*")
        case .antigravity: .grouped(event: "PreToolUse", matcher: "run_command")
        case .cursor: .flat(event: "beforeShellExecution") { ["command": $0] }
        case .copilot: .flat(event: "permissionRequest") { ["type": "command", "bash": $0, "timeoutSec": timeout] }
        }
    }

    public static func defaultURL(for kind: AgentKind) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch kind {
        case .claude: return home.appendingPathComponent(".claude/settings.json")
        case .codex: return home.appendingPathComponent(".codex/hooks.json")
        case .antigravity: return home.appendingPathComponent(".gemini/config/hooks.json")
        case .cursor: return home.appendingPathComponent(".cursor/hooks.json")
        case .copilot:
            let base = ProcessInfo.processInfo.environment["COPILOT_HOME"].map { URL(fileURLWithPath: $0) }
                ?? home.appendingPathComponent(".copilot")
            // A file of our own: Copilot reads every file in its hooks folder.
            return base.appendingPathComponent("hooks/dynamic-ledge.json")
        }
    }

    /// Where the settings file lives, shortened for showing in Settings ("~/.codex/hooks.json").
    public static func displayPath(for kind: AgentKind) -> String {
        let path = defaultURL(for: kind).path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    /// The shell command a tool runs: the app's own executable, which answers and quits.
    public static func command(executable: String, socket: String, kind: AgentKind) -> String {
        var command = "\(quote(executable)) \(flag) \(quote(socket))"
        if kind != .claude { command += " \(agentFlag) \(kind.rawValue)" }
        return command
    }

    /// The command for this copy of the app.
    public static func currentCommand(socket: String, kind: AgentKind) -> String? {
        Bundle.main.executablePath.map { command(executable: $0, socket: socket, kind: kind) }
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func isInstalled(_ kind: AgentKind, at url: URL? = nil) -> Bool {
        guard let settings = try? readExisting(url ?? defaultURL(for: kind)) else { return false }
        return commands(in: settings, kind: kind).contains(where: isOurs)
    }

    /// True when our hook is there with exactly this command (false after the app moved).
    public static func isCurrent(_ kind: AgentKind, command: String, at url: URL? = nil) -> Bool {
        guard let settings = try? readExisting(url ?? defaultURL(for: kind)) else { return false }
        return commands(in: settings, kind: kind).contains(command)
    }

    /// Adds the hook (replacing an older one of ours, say from before the app moved).
    public static func install(_ kind: AgentKind, command: String, at url: URL? = nil) throws {
        let url = url ?? defaultURL(for: kind)
        var settings = try read(url)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        switch layout(for: kind) {
        case .grouped(let event, let matcher):
            var groups = (hooks[event] as? [[String: Any]] ?? []).compactMap(withoutOurs)
            groups.append([
                "matcher": matcher,
                "hooks": [["type": "command", "command": command, "timeout": timeout]],
            ])
            hooks[event] = groups
        case .flat(let event, let entry):
            var entries = (hooks[event] as? [[String: Any]] ?? []).filter { !isOurs(entryCommand($0)) }
            entries.append(entry(command))
            hooks[event] = entries
            if settings["version"] == nil { settings["version"] = 1 }
        }
        settings["hooks"] = hooks
        try write(settings, to: url)
    }

    public static func uninstall(_ kind: AgentKind, at url: URL? = nil) throws {
        let url = url ?? defaultURL(for: kind)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var settings = try read(url)
        guard commands(in: settings, kind: kind).contains(where: isOurs),
              var hooks = settings["hooks"] as? [String: Any] else { return }
        let event: String
        let kept: [[String: Any]]
        switch layout(for: kind) {
        case .grouped(let name, _):
            event = name
            kept = (hooks[name] as? [[String: Any]] ?? []).compactMap(withoutOurs)
        case .flat(let name, _):
            event = name
            kept = (hooks[name] as? [[String: Any]] ?? []).filter { !isOurs(entryCommand($0)) }
        }
        if kept.isEmpty { hooks[event] = nil } else { hooks[event] = kept }
        if hooks.isEmpty { settings["hooks"] = nil } else { settings["hooks"] = hooks }
        if case .flat = layout(for: kind), settings.keys.sorted() == ["version"] { settings = [:] }
        // A file that was only ever ours (Copilot's) goes away completely.
        if settings.isEmpty, kind == .copilot {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try write(settings, to: url)
    }

    // MARK: Helpers

    private static func object(from data: Data) throws -> [String: Any] {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.unreadable }
        return object
    }

    private static func readExisting(_ url: URL) throws -> [String: Any] {
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }
        return try object(from: data)
    }

    private static func read(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }
        return try object(from: data)
    }

    private static func write(_ settings: [String: Any], to url: URL) throws {
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            // Many people keep these files as links into a dotfiles folder: write through the link
            // instead of replacing it, and keep the file's permissions.
            let target = url.resolvingSymlinksInPath()
            let permissions = (try? FileManager.default.attributesOfItem(atPath: target.path))?[.posixPermissions]
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
            if let permissions {
                try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
            }
        } catch {
            throw Failure.unwritable
        }
    }

    /// Every hook command registered for the event this tool uses.
    private static func commands(in settings: [String: Any], kind: AgentKind) -> [String] {
        let hooks = settings["hooks"] as? [String: Any] ?? [:]
        switch layout(for: kind) {
        case .grouped(let event, _):
            let groups = hooks[event] as? [[String: Any]] ?? []
            return groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }.compactMap { $0["command"] as? String }
        case .flat(let event, _):
            return (hooks[event] as? [[String: Any]] ?? []).compactMap(entryCommand)
        }
    }

    private static func entryCommand(_ entry: [String: Any]) -> String? {
        entry["command"] as? String ?? entry["bash"] as? String
    }

    private static func isOurs(_ command: String?) -> Bool {
        command?.contains(" \(flag) ") == true
    }

    /// The group without our hook, or nil when nothing else is left in it.
    private static func withoutOurs(_ group: [String: Any]) -> [String: Any]? {
        guard let entries = group["hooks"] as? [[String: Any]] else { return group }
        let kept = entries.filter { !isOurs($0["command"] as? String) }
        if kept.count == entries.count { return group }
        if kept.isEmpty { return nil }
        var copy = group
        copy["hooks"] = kept
        return copy
    }
}
