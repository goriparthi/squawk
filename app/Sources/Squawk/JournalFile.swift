import Foundation
import SquawkCore

/// The week's journal on disk, beside the config and with the same permissions.
/// It holds what your agents asked for and what you said, which is the pet's
/// memory and nobody else's business.
enum JournalFile {
    static var path: String {
        (SocketPath.directory(home: NSHomeDirectory()) as NSString)
            .appendingPathComponent("journal.json")
    }

    static func load() -> Journal {
        guard let data = FileManager.default.contents(atPath: path),
              var journal = try? JSONDecoder().decode(Journal.self, from: data)
        else { return Journal() }
        // A week old the moment it is read back, so it is trimmed on the way in
        // rather than waiting for the next thing to happen.
        journal.prune()
        return journal
    }

    static func save(_ journal: Journal) {
        guard let data = try? JSONEncoder().encode(journal) else { return }
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory,
                                                 withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    static func erase() {
        try? FileManager.default.removeItem(atPath: path)
    }
}
