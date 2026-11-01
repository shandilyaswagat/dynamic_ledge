import Foundation
import Security

/// Runs when a coding assistant calls the app as its permission hook (`DynamicNotch --agent-hook
/// <socket> --agent <kind>`): hands the request to the running app and prints its answer.
/// Whenever anything goes wrong (the app isn't running, no answer) it prints the assistant's
/// "ask as usual" answer, so its own prompt appears. It never allows anything on its own.
public enum AgentHookClient {
    public static func runIfRequested(_ arguments: [String] = CommandLine.arguments) {
        guard let index = arguments.firstIndex(of: AgentHookSettings.flag) else { return }
        let socket = arguments.indices.contains(index + 1) ? arguments[index + 1] : AgentBridge.defaultSocketPath
        let kind = arguments.firstIndex(of: AgentHookSettings.agentFlag)
            .flatMap { arguments.indices.contains($0 + 1) ? AgentKind(rawValue: arguments[$0 + 1]) : nil } ?? .claude
        let input = FileHandle.standardInput.readDataToEndOfFile()
        if arguments.contains(AgentHookSettings.finishedFlag) {
            // Just news for the notch: tell it, never wait for it, and let the tool stop.
            _ = exchange(input: input, socket: socket, kind: kind, finished: true)
            FileHandle.standardOutput.write(kind.finishedOutput)
            exit(0)
        }
        let output = answer(input: input, socket: socket, kind: kind)
        FileHandle.standardOutput.write(output)
        exit(0)
    }

    static func answer(input: Data, socket path: String, kind: AgentKind = .claude) -> Data {
        let reply = exchange(input: input, socket: path, kind: kind)
        return reply.isEmpty ? kind.fallbackOutput : reply
    }

    /// Authenticate the connected process, not the replaceable socket pathname. The app must
    /// meet this copy's designated requirement: for a release, any build signed with the
    /// Dynamic Ledge certificate under the same app ID, so approvals keep working when the app
    /// on disk is updated before the running one restarts. An ad-hoc test build's requirement
    /// is its exact code hash. Audit tokens avoid PID reuse.
    static func trustsPeer(_ fd: Int32) -> Bool {
        authenticatedPeer(fd) != nil
    }

    private static func authenticatedPeer(_ fd: Int32) -> SecCode? {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { return nil }
        var token = audit_token_t()
        var size = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &size) == 0,
              size == MemoryLayout<audit_token_t>.size else { return nil }
        let audit = withUnsafeBytes(of: token) { Data($0) }
        var peer: SecCode?
        var own: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: audit] as CFDictionary, [], &peer) == errSecSuccess,
              let peer,
              SecCodeCopySelf([], &own) == errSecSuccess, let own else { return nil }
        var ownStatic: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopyStaticCode(own, [], &ownStatic) == errSecSuccess, let ownStatic,
              SecCodeCopyDesignatedRequirement(ownStatic, [], &requirement) == errSecSuccess,
              let requirement else { return nil }
        guard SecCodeCheckValidity(peer, [], requirement) == errSecSuccess else { return nil }
        return peer
    }

    /// The app's reply, or nothing.
    private static func exchange(input: Data, socket path: String, kind: AgentKind, finished: Bool = false) -> Data {
        guard !input.isEmpty, input.count <= AgentSocketServer.maximumRequest else { return Data() }
        // Tell the app which assistant is asking. A finished notice carries only the folder name.
        guard let inner = try? JSONSerialization.jsonObject(with: input) else { return Data() }
        let message: [String: Any] = finished
            ? ["agent": kind.rawValue, "finished": true, "project": Self.project(in: inner)]
            : ["agent": kind.rawValue, "input": inner]
        guard let wrapped = try? JSONSerialization.data(withJSONObject: message) else { return Data() }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return Data() }
        defer { close(fd) }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        // Give up a little before the assistant does: Antigravity blocks a command whose hook
        // times out, so it must always get an answer.
        var limit = timeval(tv_sec: finished ? 2 : AgentHookSettings.timeout - 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { return Data() }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0, let peer = authenticatedPeer(fd) else { return Data() }

        // One line: compact JSON has no raw newlines.
        var line = wrapped
        line.append(0x0A)
        let sent = line.withUnsafeBytes { buffer -> Bool in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
        guard sent, !finished else { return Data() }

        var reply = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while !reply.contains(0x0A) {
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { break }
            reply.append(contentsOf: chunk[0..<count])
            if reply.count > 65_536 { return Data() }
        }
        guard SecCodeCheckValidity(peer, [], nil) == errSecSuccess, let newline = reply.firstIndex(of: 0x0A) else { return Data() }
        return Data(reply[..<newline])
    }

    /// The name of the folder the assistant worked in, from whichever field its tool uses.
    static func project(in input: Any) -> String {
        let object = input as? [String: Any] ?? [:]
        let folder = (object["cwd"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (object["workspace_roots"] as? [String])?.first
            ?? ""
        return folder.isEmpty ? "" : URL(fileURLWithPath: folder).lastPathComponent
    }
}
