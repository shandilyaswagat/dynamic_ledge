import Foundation

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
        let output = answer(input: FileHandle.standardInput.readDataToEndOfFile(), socket: socket, kind: kind)
        FileHandle.standardOutput.write(output)
        exit(0)
    }

    static func answer(input: Data, socket path: String, kind: AgentKind = .claude) -> Data {
        let reply = exchange(input: input, socket: path, kind: kind)
        return reply.isEmpty ? kind.fallbackOutput : reply
    }

    /// The app's reply, or nothing.
    private static func exchange(input: Data, socket path: String, kind: AgentKind) -> Data {
        guard !input.isEmpty, input.count <= AgentSocketServer.maximumRequest else { return Data() }
        // Tell the app which assistant is asking.
        guard let inner = try? JSONSerialization.jsonObject(with: input),
              let wrapped = try? JSONSerialization.data(withJSONObject: ["agent": kind.rawValue, "input": inner]) else { return Data() }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return Data() }
        defer { close(fd) }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        // Give up a little before the assistant does: Antigravity blocks a command whose hook
        // times out, so it must always get an answer.
        var limit = timeval(tv_sec: AgentHookSettings.timeout - 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { return Data() }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return Data() }

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
        guard sent else { return Data() }

        var reply = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while !reply.contains(0x0A) {
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { break }
            reply.append(contentsOf: chunk[0..<count])
            if reply.count > 65_536 { return Data() }
        }
        guard let newline = reply.firstIndex(of: 0x0A) else { return Data() }
        return Data(reply[..<newline])
    }
}
