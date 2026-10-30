import Foundation

/// Runs when Claude Code calls the app as its permission hook (`DynamicNotch --agent-hook
/// <socket>`): hands the request to the running app and prints its answer. Whenever anything
/// goes wrong (the app isn't running, no answer) it prints nothing, and Claude Code asks in its
/// own window as usual. It never allows anything on its own.
public enum AgentHookClient {
    public static func runIfRequested(_ arguments: [String] = CommandLine.arguments) {
        guard let index = arguments.firstIndex(of: ClaudeHookSettings.flag) else { return }
        let socket = arguments.indices.contains(index + 1) ? arguments[index + 1] : AgentBridge.defaultSocketPath
        let output = answer(input: FileHandle.standardInput.readDataToEndOfFile(), socket: socket)
        FileHandle.standardOutput.write(output)
        exit(0)
    }

    static func answer(input: Data, socket path: String) -> Data {
        guard !input.isEmpty, input.count <= AgentSocketServer.maximumRequest else { return Data() }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return Data() }
        defer { close(fd) }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        // Never outlast Claude Code's own wait.
        var limit = timeval(tv_sec: ClaudeHookSettings.timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else { return Data() }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { return Data() }

        // One line: the request with its newlines removed (JSON doesn't need them).
        var line = Data(input.filter { $0 != 0x0A && $0 != 0x0D })
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
