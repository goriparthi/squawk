import Foundation
import SquawkCore

/// Accepts hook connections and holds each one open until the panel answers.
/// One thread per connection: the count is bounded by concurrent agent sessions,
/// which is a handful, and a blocked read is the natural shape of "waiting".
final class RequestServer: @unchecked Sendable {
    typealias Handler = @Sendable (PendingRequest, @escaping @Sendable (DecisionReply) -> Void) -> Void
    /// The hook went away before answering, so its arc must go too.
    typealias Abandoned = @Sendable (String) -> Void

    private let path: String
    private let handler: Handler
    private let abandoned: Abandoned
    private var listenFD: Int32 = -1
    private let queue = DispatchQueue(label: "squawk.server", qos: .userInitiated)
    private var running = false

    init(path: String, handler: @escaping Handler, abandoned: @escaping Abandoned) {
        self.path = path
        self.handler = handler
        self.abandoned = abandoned
    }

    func start() throws {
        let directory = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        listenFD = try UnixSocket.listen(on: path)
        running = true
        queue.async { [weak self] in self?.acceptLoop() }
    }

    func stop() {
        running = false
        if listenFD >= 0 { close(listenFD) }
        listenFD = -1
        unlink(path)
    }

    private func acceptLoop() {
        while running {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else {
                if errno == EINTR { continue }
                return
            }
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.serve(fd)
            }
        }
    }

    private func serve(_ fd: Int32) {
        defer { close(fd) }
        guard let line = try? UnixSocket.readLine(fd),
              let request = try? WireCodec.decode(PendingRequest.self, from: line)
        else { return }

        // Nothing is blocked on an attention entry, so it is posted and the
        // connection closes. Holding it open would pin a thread for nothing.
        guard request.awaitsDecision else {
            handler(request) { _ in }
            return
        }

        let gate = DispatchSemaphore(value: 0)
        let box = ReplyBox()
        handler(request) { reply in
            box.set(reply)
            gate.signal()
        }

        // Waiting in slices rather than one blocking wait, so a hook that dies
        // before answering is noticed. Its deadline alone is not enough: kill the
        // agent and the arc would linger, still clickable, answering nobody.
        while gate.wait(timeout: .now() + 0.4) == .timedOut {
            if Self.peerHasGone(fd) {
                abandoned(request.id)
                return
            }
        }
        guard let reply = box.value, let data = try? WireCodec.encode(reply) else { return }
        try? UnixSocket.writeAll(fd, data)
    }

    /// A zero length peek means the peer closed. The hook never sends a second
    /// line, so anything readable here is unexpected and left alone.
    static func peerHasGone(_ fd: Int32) -> Bool {
        var byte: UInt8 = 0
        let seen = recv(fd, &byte, 1, MSG_PEEK | MSG_DONTWAIT)
        if seen == 0 { return true }
        if seen < 0 { return !(errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) }
        return false
    }
}

private final class ReplyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: DecisionReply?

    var value: DecisionReply? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func set(_ reply: DecisionReply) {
        lock.lock(); defer { lock.unlock() }
        stored = reply
    }
}
