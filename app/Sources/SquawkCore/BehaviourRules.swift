import Foundation

/// The instructions handed to a local model, in a file the app re-reads rather
/// than compiled in.
///
/// From murmur. What a small model is told is the sort of thing you want to
/// change six times in an evening, and a rebuild between each one means it
/// never gets tuned at all. `~/.squawk/behaviour.md` holds it; delete the file
/// and the built-in text comes back.
///
/// It is not a plugin system and must never become one. The file chooses the
/// *wording* of instructions the app was already going to send. It cannot add
/// a section, reach anything else, or change what a reply is checked against:
/// `Phrasing.accept` still throws away a reply that drops a project or a risk
/// warning, whatever this file says.
public struct BehaviourRules: Sendable, Equatable {
    /// The sections it may set, named as they appear in the file. Anything else
    /// is ignored rather than an error: a stray heading in someone's notes
    /// should not empty out the instructions.
    public enum Section: String, CaseIterable, Sendable {
        /// Rewording a status report it is about to say out loud.
        case phrasing
        /// Answering a question of its own.
        case answering
    }

    /// Long enough for real instructions, short enough that it cannot crowd out
    /// the facts. A small model given two pages answers the pages.
    public static let longest = 1_200

    private var sections: [Section: String]

    public init(sections: [Section: String] = [:]) {
        self.sections = sections
    }

    /// The wording for a section, or the built-in text when the file says
    /// nothing useful about it.
    public func instruction(for section: Section, fallback: String) -> String {
        guard let text = sections[section], !text.isEmpty else { return fallback }
        return text
    }

    /// Parses the file. Markdown headings name the sections and everything
    /// under one is its text, so the file reads as notes rather than as config.
    ///
    /// Never throws and never returns nothing useful from a partly broken file:
    /// this is someone's scratch file, and half of it working beats all of it
    /// being discarded because one heading was misspelled.
    public static func parse(_ markdown: String) -> BehaviourRules {
        var sections: [Section: String] = [:]
        var current: Section?
        var lines: [String] = []

        func close() {
            guard let current else { return }
            let text = lines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                sections[current] = ToolSummary.truncate(text, to: longest)
            }
            lines = []
        }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#") else {
                if current != nil { lines.append(line) }
                continue
            }
            close()
            let heading = trimmed
                .drop { $0 == "#" }
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            // An unknown heading closes whatever was open and opens nothing, so
            // its body is not silently appended to the section above it.
            current = Section(rawValue: heading)
        }
        close()
        return BehaviourRules(sections: sections)
    }

    public static func path(home: String = NSHomeDirectory()) -> String {
        (SocketPath.directory(home: home) as NSString)
            .appendingPathComponent("behaviour.md")
    }

    /// What the file says now. Absent or unreadable is not a failure: it means
    /// the built-in wording, which is the state most people will be in.
    public static func load(path: String = path()) -> BehaviourRules {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8)
        else { return BehaviourRules() }
        return parse(text)
    }

    /// What the file looks like when it has never been written, with the
    /// built-in wording in it so there is something to edit rather than a blank
    /// page and a guess at the headings.
    public static func template(phrasing: String, answering: String) -> String {
        """
        # Squawk behaviour

        What the local model is told. Edit and save; Squawk re-reads this by
        itself. Delete the file to go back to the built-in wording.

        Only the two headings below are read. This is the wording of
        instructions Squawk was already going to send, not a way to add new
        ones, and nothing here relaxes the checks a reply is put through.

        # phrasing

        \(phrasing)

        # answering

        \(answering)
        """
    }
}
