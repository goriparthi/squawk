import Foundation
import SquawkCore

/// A record of what it heard and what it did about it, for working out why a
/// spoken command went nowhere. Written only while listening is switched on,
/// kept to the last few hundred lines, and readable by nobody else.
///
/// It contains speech, so it says so in its own first line and the menu offers
/// a way to delete it. The app writes a transcript nowhere else.
@MainActor
enum ListeningLog {
    nonisolated static var path: String {
        (SocketPath.directory(home: NSHomeDirectory()) as NSString)
            .appendingPathComponent("listening.log")
    }

    private static let limit = 400
    private static var lines: [String] = []
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static func note(_ line: String) {
        guard Settings.logsListening else { return }
        if lines.isEmpty {
            lines.append("This file records what Squawk heard while listening was on. "
                + "It contains speech, and only exists while listening is switched on. "
                + "Delete it whenever you like: rm ~/.squawk/listening.log")
        }
        lines.append("\(formatter.string(from: Date()))  \(line)")
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    static func clear() {
        lines.removeAll()
        try? FileManager.default.removeItem(atPath: path)
    }
}
