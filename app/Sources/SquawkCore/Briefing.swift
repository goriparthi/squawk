import Foundation

/// What the pet would tell you about your agents, as structure rather than as a
/// sentence. Pure, so the rules are testable and whatever phrases it (a
/// template here, or a model on the machine) is handed facts it cannot invent.
public struct Briefing: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        /// The directory the agent is working in, which is how people name
        /// their work. Nobody thinks in session ids.
        public let project: String
        public let tool: String
        public let summary: String
        public let risky: Bool
        /// False for an agent that wants you rather than an answer.
        public let awaitsDecision: Bool
        public let waited: TimeInterval

        public init(project: String, tool: String, summary: String, risky: Bool,
                    awaitsDecision: Bool, waited: TimeInterval) {
            self.project = project
            self.tool = tool
            self.summary = summary
            self.risky = risky
            self.awaitsDecision = awaitsDecision
            self.waited = waited
        }
    }

    public let items: [Item]

    public init(items: [Item]) { self.items = items }

    public var waiting: Int { items.count }
    public var decisions: Int { items.filter(\.awaitsDecision).count }
    public var attention: Int { items.count - decisions }
    public var risky: Int { items.filter(\.risky).count }

    public static func item(for request: PendingRequest, waited: TimeInterval = 0) -> Item {
        Item(project: request.project,
             tool: request.tool,
             summary: ToolSummary.redact(request.summary),
             risky: request.awaitsDecision
                 && RiskSignal.isRisky(tool: request.tool, summary: request.summary),
             awaitsDecision: request.awaitsDecision,
             waited: max(0, waited))
    }

    /// Longest wait first: the one that has been sitting there is the one worth
    /// naming when there is only room to name one.
    public static func of(_ roster: Roster, now: Date = Date()) -> Briefing {
        let items = roster.entries
            .map { item(for: $0.request, waited: now.timeIntervalSince($0.arrivedAt)) }
            .sorted { $0.waited > $1.waited }
        return Briefing(items: items)
    }
}

/// Turns a briefing into something to say out loud. This is both the voice when
/// nothing else is available and the material a local model is asked to rephrase,
/// so it never states anything the briefing does not.
public enum Utterance {
    /// How many are named before it stops listing and gives a count. Spoken
    /// aloud, a list of four is not a report, it is a queue nobody can hold.
    public static let namedLimit = 2

    public static func spoken(_ briefing: Briefing) -> String {
        guard briefing.waiting > 0 else { return "Nothing waiting." }
        var parts = [headline(briefing)]
        for item in briefing.items.prefix(namedLimit) { parts.append(sentence(for: item)) }
        if briefing.waiting > namedLimit {
            let rest = briefing.waiting - namedLimit
            parts.append("And \(count(rest)) more.")
        }
        return parts.joined(separator: " ")
    }

    private static func headline(_ briefing: Briefing) -> String {
        let waiting = "\(count(briefing.waiting).capitalizedFirst) waiting"
        // Only worth splitting out when the two numbers differ: "two waiting,
        // two need a decision" is the same sentence said twice.
        guard briefing.decisions > 0, briefing.decisions < briefing.waiting else {
            return waiting + "."
        }
        return waiting + ", \(count(briefing.decisions)) needing a decision."
    }

    /// One arrival, announced on its own. The whole briefing on every arrival
    /// is a pet reading you the queue every time it grows by one.
    public static func arrival(_ item: Briefing.Item) -> String { sentence(for: item) }

    private static func sentence(for item: Item) -> String {
        guard item.awaitsDecision else { return "\(item.project) wants you." }
        var line = "\(item.project) wants \(item.tool): \(trimmed(item.summary))."
        if item.risky { line += " That one looks risky." }
        return line
    }

    /// Spoken, not read: a long command is a wall of syllables nobody can
    /// follow, and the bubble already has the whole of it.
    static func trimmed(_ summary: String) -> String {
        ToolSummary.truncate(ToolSummary.sanitize(summary), to: 60)
    }

    /// Small numbers are words. "1 waiting" read aloud is a robot reading a
    /// spreadsheet; "one waiting" is someone telling you something.
    static func count(_ number: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five",
                     "six", "seven", "eight", "nine", "ten"]
        return number >= 0 && number < words.count ? words[number] : "\(number)"
    }
}

private typealias Item = Briefing.Item

private extension String {
    var capitalizedFirst: String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
}
