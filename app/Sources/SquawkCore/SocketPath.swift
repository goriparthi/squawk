import Foundation

/// Where the app listens and the hook connects. Kept under the user's home so
/// the socket inherits home directory permissions rather than world writable /tmp.
public enum SocketPath {
    public static let directoryName = ".squawk"
    public static let socketName = "sock"

    public static func directory(home: String) -> String {
        (home as NSString).appendingPathComponent(directoryName)
    }

    public static func socket(home: String) -> String {
        (directory(home: home) as NSString).appendingPathComponent(socketName)
    }

    public static var defaultSocket: String {
        socket(home: NSHomeDirectory())
    }

    /// sockaddr_un caps the path at 104 bytes on Darwin, and a silent truncation
    /// binds the wrong path, so callers check rather than discover it at connect.
    public static let maxLength = 103

    public static func isRepresentable(_ path: String) -> Bool {
        path.utf8.count <= maxLength
    }
}
