import Foundation

/// A coding assistant (Claude Code) asking whether it may use a tool, answered from the notch.
public struct AgentRequest: Equatable, Sendable, Identifiable {
    public var id: UUID
    /// "Claude Code".
    public var agent: String
    /// The folder the assistant is working in, by name.
    public var project: String
    public var toolName: String
    /// What the assistant wants to do, in one short line ("Run a command").
    public var title: String
    /// The command, file or address it applies to.
    public var detail: String

    public init(id: UUID = UUID(), agent: String, project: String, toolName: String, title: String, detail: String) {
        self.id = id
        self.agent = agent
        self.project = project
        self.toolName = toolName
        self.title = title
        self.detail = detail
    }

    /// The longest detail kept; the notch shows two lines of it.
    static let maximumDetail = 600

    /// Reads Claude Code's PermissionRequest hook input. Nil when it isn't one.
    public init?(claudeHookInput data: Data, id: UUID = UUID()) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["hook_event_name"] as? String == "PermissionRequest",
            let tool = object["tool_name"] as? String, !tool.isEmpty
        else { return nil }
        let input = object["tool_input"] as? [String: Any] ?? [:]
        let cwd = object["cwd"] as? String ?? ""
        let (title, detail) = Self.describe(tool: tool, input: input, cwd: cwd)
        self.init(
            id: id,
            agent: "Claude Code",
            project: cwd.isEmpty ? "" : URL(fileURLWithPath: cwd).lastPathComponent,
            toolName: tool,
            title: title,
            detail: String(detail.prefix(Self.maximumDetail))
        )
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
            return ("Edit a file", path("file_path"))
        case "Write":
            return ("Write a file", path("file_path"))
        case "NotebookEdit":
            return ("Edit a notebook", path("notebook_path"))
        case "Read":
            return ("Read a file", path("file_path"))
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

    /// What the hook prints for Claude Code. Empty for `ask`, which leaves the normal prompt.
    public var claudeHookOutput: Data {
        let decision: [String: Any]
        switch self {
        case .allow: decision = ["behavior": "allow"]
        case .deny: decision = ["behavior": "deny", "message": "Denied from Dynamic Ledge."]
        case .ask: return Data()
        }
        let output: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        return (try? JSONSerialization.data(withJSONObject: output, options: .sortedKeys)) ?? Data()
    }
}

/// Adds or removes Dynamic Ledge's hook in Claude Code's settings (~/.claude/settings.json),
/// leaving everything else in the file as it was.
public enum ClaudeHookSettings {
    /// Marks our hook, so it's found again whatever path the app is at.
    public static let flag = "--agent-hook"
    /// Seconds Claude Code waits for an answer before asking in its own window.
    public static let timeout = 120

    public enum Failure: Error, Equatable {
        /// The file exists but isn't a JSON object; it's left untouched.
        case unreadable
        case unwritable
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    /// The shell command Claude Code runs: the app's own executable, which answers and quits.
    public static func command(executable: String, socket: String) -> String {
        "\(quote(executable)) \(flag) \(quote(socket))"
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// True when our hook is there with exactly this command (false after the app moved).
    public static func isCurrent(command: String, at url: URL = defaultURL) -> Bool {
        guard let data = try? Data(contentsOf: url), let settings = try? object(from: data) else { return false }
        return entries(in: settings).contains { $0["command"] as? String == command }
    }

    /// The command for this copy of the app.
    public static func currentCommand(socket: String) -> String? {
        Bundle.main.executablePath.map { command(executable: $0, socket: socket) }
    }

    public static func isInstalled(at url: URL = defaultURL) -> Bool {
        guard let data = try? Data(contentsOf: url), let settings = try? object(from: data) else { return false }
        return entries(in: settings).contains(where: isOurs)
    }

    /// Adds the hook (replacing an older one of ours, say from before the app moved).
    public static func install(command: String, at url: URL = defaultURL) throws {
        var settings = try read(url)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var groups = (hooks["PermissionRequest"] as? [[String: Any]] ?? []).compactMap(withoutOurs)
        groups.append([
            "matcher": "*",
            "hooks": [["type": "command", "command": command, "timeout": timeout]],
        ])
        hooks["PermissionRequest"] = groups
        settings["hooks"] = hooks
        try write(settings, to: url)
    }

    public static func uninstall(at url: URL = defaultURL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var settings = try read(url)
        guard entries(in: settings).contains(where: isOurs),
              var hooks = settings["hooks"] as? [String: Any],
              let groups = hooks["PermissionRequest"] as? [[String: Any]] else { return }
        let kept = groups.compactMap(withoutOurs)
        if kept.isEmpty { hooks["PermissionRequest"] = nil } else { hooks["PermissionRequest"] = kept }
        if hooks.isEmpty { settings["hooks"] = nil } else { settings["hooks"] = hooks }
        try write(settings, to: url)
    }

    // MARK: Helpers

    private static func object(from data: Data) throws -> [String: Any] {
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.unreadable }
        return object
    }

    private static func read(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let data = try? Data(contentsOf: url) else { throw Failure.unreadable }
        return try object(from: data)
    }

    private static func write(_ settings: [String: Any], to url: URL) throws {
        do {
            let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw Failure.unwritable
        }
    }

    private static func entries(in settings: [String: Any]) -> [[String: Any]] {
        let groups = (settings["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]] ?? []
        return groups.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
    }

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry["command"] as? String)?.contains(" \(flag) ") == true
    }

    /// The group without our hook, or nil when nothing else is left in it.
    private static func withoutOurs(_ group: [String: Any]) -> [String: Any]? {
        guard let entries = group["hooks"] as? [[String: Any]] else { return group }
        let kept = entries.filter { !isOurs($0) }
        if kept.count == entries.count { return group }
        if kept.isEmpty { return nil }
        var copy = group
        copy["hooks"] = kept
        return copy
    }
}
