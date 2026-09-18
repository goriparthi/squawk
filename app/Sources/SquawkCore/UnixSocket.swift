import Foundation

public enum SocketError: Error, Equatable {
    case pathTooLong
    case create(Int32)
    case connect(Int32)
    case bind(Int32)
    case listen(Int32)
    case timedOut
    case closed
}

/// A blocking Unix domain socket with deadlines on both directions. Small and
/// hand rolled because the app ships no package dependencies.
public enum UnixSocket {
    public static func makeAddress(path: String) throws -> sockaddr_un {
        guard SocketPath.isRepresentable(path) else { throw SocketError.pathTooLong }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            path.withCString { source in
                strncpy(
                    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: CChar.self),
                    source,
                    SocketPath.maxLength
                )
            }
        }
        return address
    }

    public static func connect(to path: String, timeout: TimeInterval) throws -> Int32 {
        var address = try makeAddress(path: path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.create(errno) }

        setTimeout(fd, SO_SNDTIMEO, timeout)
        setTimeout(fd, SO_RCVTIMEO, timeout)

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            let code = errno
            close(fd)
            throw SocketError.connect(code)
        }
        return fd
    }

    public static func listen(on path: String, backlog: Int32 = 16) throws -> Int32 {
        unlink(path)
        var address = try makeAddress(path: path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.create(errno) }

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw SocketError.bind(code)
        }
        // The socket carries approval authority, so only its owner may speak to it.
        chmod(path, 0o600)
        guard Darwin.listen(fd, backlog) == 0 else {
            let code = errno
            close(fd)
            throw SocketError.listen(code)
        }
        return fd
    }

    public static func writeAll(_ fd: Int32, _ data: Data) throws {
        try data.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let written = Darwin.write(fd, buffer.baseAddress!.advanced(by: sent), buffer.count - sent)
                if written > 0 {
                    sent += written
                    continue
                }
                if written < 0, errno == EINTR { continue }
                if written < 0, errno == EAGAIN || errno == EWOULDBLOCK { throw SocketError.timedOut }
                throw SocketError.closed
            }
        }
    }

    /// Reads one newline terminated frame. The cap stops a peer from growing the
    /// buffer without bound.
    public static func readLine(_ fd: Int32, limit: Int = 1 << 20) throws -> Data {
        var buffer = Data()
        var byte: UInt8 = 0
        while buffer.count < limit {
            let read = Darwin.read(fd, &byte, 1)
            if read == 1 {
                if byte == 0x0A { return buffer }
                buffer.append(byte)
                continue
            }
            if read < 0, errno == EINTR { continue }
            if read < 0, errno == EAGAIN || errno == EWOULDBLOCK { throw SocketError.timedOut }
            throw SocketError.closed
        }
        throw SocketError.closed
    }

    public static func setTimeout(_ fd: Int32, _ option: Int32, _ seconds: TimeInterval) {
        var tv = timeval(
            tv_sec: Int(seconds),
            tv_usec: Int32((seconds - Double(Int(seconds))) * 1_000_000)
        )
        setsockopt(fd, SOL_SOCKET, option, &tv, socklen_t(MemoryLayout<timeval>.size))
    }
}
