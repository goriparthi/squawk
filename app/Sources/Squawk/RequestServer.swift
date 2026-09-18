import Foundation
import SquawkCore

/// Accepts hook connections and holds each one open until the panel answers.
/// One thread per connection: the count is bounded by concurrent agent sessions,
/// which is a handful, and a blocked read is the natural shape of "waiting".
final class RequestServer: @unchecked Sendable {
    typealias Handler = @Sendable (PendingRequest, @escaping @Sendable (DecisionReply) -> Void) -> Void

    private let path: String
    private let handler: Handler
    private var listenFD: Int32 = -1
    private let queue = DispatchQueue(label: "squawk.server", qos: .userInitiated)
    private var running = false

    init(path: String, handler: @escaping Handler) {
        self.path = path
        self.handler = handler
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

        // The hook gives up on its own deadline, so this only has to outlive a
        // decision, not guarantee one.
        let gate = DispatchSemaphore(value: 0)
        let box = ReplyBox()
        handler(request) { reply in
            box.set(reply)
            gate.signal()
        }
        gate.wait()
        guard let reply = box.value, let data = try? WireCodec.encode(reply) else { return }
        try? UnixSocket.writeAll(fd, data)
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
