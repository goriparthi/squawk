import Foundation

/// A week of what actually happened: what your agents asked for, what you said,
/// and what you asked the pet. Kept because it is the one thing this assistant
/// knows that no other one does.
///
/// A general model can tell you the capital of Australia. Only this one can
/// tell you that you approved a force push in squawk an hour ago, and that is
/// the whole argument for it having a memory at all.
public struct Journal: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable {
            case approved, denied, abandoned, arrived, asked, answered
        }

        public let at: Date
        public let kind: Kind
        /// The project it happened in, when it happened in one.
        public let project: String?
        public let text: String

        public init(at: Date, kind: Kind, project: String?, text: String) {
            self.at = at
            self.kind = kind
            self.project = project
            self.text = text
        }
    }

    /// A week. Long enough to answer "what did I do on Monday", short enough
    /// that a record of someone's desk is not kept indefinitely.
    public static let keepFor: TimeInterval = 7 * 24 * 60 * 60
    /// A hard ceiling as well as a time one: a busy week must not grow without
    /// limit, and nothing here is worth unbounded disk.
    public static let mostEntries = 4_000

    public private(set) var entries: [Entry] = []

    public init(entries: [Entry] = []) { self.entries = entries }

    public mutating func add(_ entry: Entry, now: Date = Date()) {
        entries.append(entry)
        prune(now: now)
    }

    public mutating func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Self.keepFor)
        entries.removeAll { $0.at < cutoff }
        if entries.count > Self.mostEntries {
            entries.removeFirst(entries.count - Self.mostEntries)
        }
    }

    public func since(_ start: Date) -> [Entry] { entries.filter { $0.at >= start } }

    public func count(_ kind: Entry.Kind, since start: Date) -> Int {
        entries.lazy.filter { $0.at >= start && $0.kind == kind }.count
    }

    /// The projects worked in, most recent first.
    public func projects(since start: Date) -> [String] {
        var seen: [String] = []
        for entry in entries.reversed() where entry.at >= start {
            guard let project = entry.project, !seen.contains(project) else { continue }
            seen.append(project)
        }
        return seen
    }

    /// What the day looks like, in a line or two, for handing to a model. Facts
    /// only: it is the grounding, not the answer.
    public func today(now: Date = Date(), calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: now)
        let approved = count(.approved, since: start)
        let denied = count(.denied, since: start)
        guard approved + denied > 0 else { return "Nothing has been approved or denied today." }
        var line = "Today you approved \(approved) and denied \(denied)"
        let worked = projects(since: start).prefix(4)
        if !worked.isEmpty { line += ", across \(worked.joined(separator: ", "))" }
        return line + "."
    }

    /// The last few things that happened, oldest first, for a question about
    /// what has been going on. Questions and answers are left out: what it was
    /// asked a minute ago is already in the conversation, and repeating it back
    /// as fact is how a model ends up quoting itself.
    public func recent(_ limit: Int = 6, now: Date = Date()) -> [String] {
        entries
            .filter { $0.kind != .asked && $0.kind != .answered }
            .suffix(limit)
            .map { entry in
                let ago = Journal.ago(from: entry.at, to: now)
                let place = entry.project.map { " in \($0)" } ?? ""
                return "\(ago): \(entry.kind.rawValue)\(place), \(ToolSummary.truncate(entry.text, to: 60))"
            }
    }

    /// Spoken, so "a moment ago" rather than a timestamp.
    public static func ago(from then: Date, to now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(then))
        if seconds < 90 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) minutes ago" }
        let hours = Int(seconds / 3600)
        if hours < 24 { return hours == 1 ? "an hour ago" : "\(hours) hours ago" }
        let days = Int(seconds / 86_400)
        return days == 1 ? "yesterday" : "\(days) days ago"
    }
}

/// Everything the pet knows about right now, as a handful of lines for a model
/// that knows none of it. Facts only, and small: a local model given two pages
/// of situation answers the situation rather than the question.
public enum Situation {
    public struct State: Sendable {
        public var now: Date
        public var place: String?
        public var briefing: Briefing
        public var journal: Journal
        public var atDeskFor: TimeInterval?
        public var playing: Bool

        public init(now: Date = Date(), place: String? = nil, briefing: Briefing = Briefing(items: []),
                    journal: Journal = Journal(), atDeskFor: TimeInterval? = nil,
                    playing: Bool = false) {
            self.now = now
            self.place = place
            self.briefing = briefing
            self.journal = journal
            self.atDeskFor = atDeskFor
            self.playing = playing
        }
    }

    public static func lines(_ state: State, calendar: Calendar = .current,
                             timeZone: TimeZone = .current) -> [String] {
        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        var where_ = ""
        if let place = state.place { where_ = ", in \(place)" }
        lines.append("It is \(formatter.string(from: state.now))\(where_).")

        if state.briefing.waiting == 0 {
            lines.append("None of their agents is waiting on them.")
        } else {
            lines.append("\(state.briefing.waiting) of their agents are waiting: "
                + state.briefing.items.prefix(3).map { item in
                    "\(item.project) wants \(item.tool)\(item.risky ? ", risky" : "")"
                }.joined(separator: "; ") + ".")
        }
        lines.append(state.journal.today(now: state.now, calendar: calendar))
        // The actual entries, not only the counts: asked which project it was,
        // a model handed a total will pick one, and it will pick wrong.
        let recent = state.journal.recent(5, now: state.now)
        if !recent.isEmpty {
            lines.append("Lately: " + recent.joined(separator: "; ") + ".")
        }
        if let atDesk = state.atDeskFor, atDesk > 45 * 60 {
            lines.append("They have been at the desk for \(Wellness.describe(atDesk)).")
        }
        if state.playing { lines.append("Music is playing.") }
        return lines
    }

    /// The whole thing as one block, ready to be a system message.
    public static func summary(_ state: State, calendar: Calendar = .current,
                               timeZone: TimeZone = .current) -> String {
        "Here is what is true right now. Use it only if the question calls for it.\n"
            + lines(state, calendar: calendar, timeZone: timeZone).joined(separator: "\n")
    }
}
