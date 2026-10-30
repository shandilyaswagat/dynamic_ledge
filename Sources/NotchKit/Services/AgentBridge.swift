import Foundation
import Observation

/// Receives permission requests from coding assistants and holds each one until it's answered
/// from the notch. Claude Code runs our hook (`AgentHookClient`), which passes the request over
/// a private socket that only this user can open, and waits for the answer.
@MainActor
@Observable
public final class AgentBridge {
    /// Waiting for an answer, oldest first. The notch shows the first.
    public private(set) var pending: [AgentRequest] = []

    /// Called whenever `pending` changes.
    @ObservationIgnored public var onChange: (() -> Void)?

    @ObservationIgnored private var server: AgentSocketServer?
    @ObservationIgnored private var connections: [UUID: Int32] = [:]
    @ObservationIgnored private var timeouts: [UUID: Task<Void, Never>] = [:]

    /// Answered with `ask` a little before Claude Code gives up on the hook, so the assistant
    /// always gets a reply and falls back to its own prompt.
    static let answerWithin: TimeInterval = TimeInterval(ClaudeHookSettings.timeout - 10)

    public let socketPath: String

    public init(socketPath: String = AgentBridge.defaultSocketPath) {
        self.socketPath = socketPath
    }

    public var isRunning: Bool { server != nil }

    public func start() {
        guard server == nil else { return }
        let server = AgentSocketServer(path: socketPath)
        server.onRequest = { [weak self] connection, data in
            Task { @MainActor in self?.received(data, on: connection) }
        }
        server.onClose = { [weak self] connection in
            Task { @MainActor in self?.closed(connection) }
        }
        guard server.start() else { return }
        self.server = server
    }

    public func stop() {
        // Anything still waiting goes back to the assistant's own prompt.
        for request in pending { answer(request.id, .ask) }
        server?.stop()
        server = nil
    }

    public func answer(_ id: UUID, _ decision: AgentDecision) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending.remove(at: index)
        timeouts.removeValue(forKey: id)?.cancel()
        if let connection = connections.removeValue(forKey: id) {
            server?.respond(on: connection, with: decision.claudeHookOutput)
        }
        onChange?()
    }

    private func received(_ data: Data, on connection: Int32) {
        guard let request = AgentRequest(claudeHookInput: data) else {
            // Not something we show: let the assistant ask as usual.
            server?.respond(on: connection, with: AgentDecision.ask.claudeHookOutput)
            return
        }
        pending.append(request)
        connections[request.id] = connection
        let id = request.id
        timeouts[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.answerWithin))
            guard !Task.isCancelled else { return }
            self?.answer(id, .ask)
        }
        onChange?()
    }

    /// The assistant stopped waiting (it was interrupted, or quit).
    private func closed(_ connection: Int32) {
        guard let id = connections.first(where: { $0.value == connection })?.key else { return }
        connections[id] = nil
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeAll { $0.id == id }
        onChange?()
    }

    /// In Application Support, named for this copy of the app so a test copy doesn't collide
    /// with the installed one. Socket paths are limited to 104 bytes, so a long home folder
    /// falls back to the private temporary folder.
    public nonisolated static var defaultSocketPath: String {
        let suffix = (Bundle.main.bundleIdentifier ?? "DynamicNotch").split(separator: ".").last.map(String.init) ?? "app"
        let name = "agent-\(suffix).sock"
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Dynamic Ledge", isDirectory: true) {
            let path = support.appendingPathComponent(name).path
            if path.utf8.count < 100 {
                try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
                return path
            }
        }
        return (NSTemporaryDirectory() as NSString).appendingPathComponent(name)
    }
}

/// A Unix socket that accepts one request per connection (a line of JSON) and keeps the
/// connection open until it's answered. Only processes of the same user may connect.
final class AgentSocketServer: @unchecked Sendable {
    var onRequest: (@Sendable (Int32, Data) -> Void)?
    var onClose: (@Sendable (Int32) -> Void)?

    private let path: String
    private let queue = DispatchQueue(label: "DynamicLedge.agent-socket")
    // Confined to `queue`.
    private var listener: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var readers: [Int32: (source: DispatchSourceRead, buffer: Data, answered: Bool)] = [:]

    /// A request bigger than this is dropped; real ones are a few kilobytes.
    static let maximumRequest = 1 << 20

    init(path: String) {
        self.path = path
    }

    func start() -> Bool {
        queue.sync { listen() }
    }

    func stop() {
        queue.sync {
            for (fd, reader) in readers {
                reader.source.cancel()
                _ = fd
            }
            readers.removeAll()
            acceptSource?.cancel()
            acceptSource = nil
            listener = -1
            unlink(path)
        }
    }

    func respond(on connection: Int32, with data: Data) {
        queue.async { [self] in
            guard var reader = readers[connection], !reader.answered else { return }
            reader.answered = true
            readers[connection] = reader
            var bytes = data
            bytes.append(0x0A)
            bytes.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let written = write(connection, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    if written <= 0 { break }
                    offset += written
                }
            }
            close(connection: connection)
        }
    }

    private func listen() -> Bool {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            Darwin.close(fd)
            return false
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: Array(path.utf8) + [0])
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 8) == 0 else {
            Darwin.close(fd)
            return false
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.accept() }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        listener = fd
        acceptSource = source
        return true
    }

    private func accept() {
        while true {
            let fd = Darwin.accept(listener, nil, nil)
            guard fd >= 0 else { return }
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
                Darwin.close(fd)
                continue
            }
            var noSigPipe: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.read(fd) }
            source.setCancelHandler { Darwin.close(fd) }
            readers[fd] = (source, Data(), false)
            source.resume()
        }
    }

    private func read(_ fd: Int32) {
        guard var reader = readers[fd] else { return }
        var chunk = [UInt8](repeating: 0, count: 16_384)
        let count = Darwin.read(fd, &chunk, chunk.count)
        if count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR) {
            let wasWaiting = reader.buffer.contains(0x0A) && !reader.answered
            close(connection: fd)
            if wasWaiting { onClose?(fd) }
            return
        }
        guard count > 0, !reader.buffer.contains(0x0A) else { return }
        reader.buffer.append(contentsOf: chunk[0..<count])
        if reader.buffer.count > Self.maximumRequest {
            close(connection: fd)
            return
        }
        readers[fd] = reader
        if let newline = reader.buffer.firstIndex(of: 0x0A) {
            onRequest?(fd, reader.buffer[..<newline])
        }
    }

    private func close(connection fd: Int32) {
        readers.removeValue(forKey: fd)?.source.cancel()
    }
}
