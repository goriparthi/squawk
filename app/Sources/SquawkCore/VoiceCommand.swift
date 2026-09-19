import Foundation

/// One waiting thing, as much of it as deciding by voice needs.
public struct SpokenTarget: Equatable, Sendable {
    public let id: String
    public let project: String
    public let risky: Bool
    public let awaitsDecision: Bool

    public init(id: String, project: String, risky: Bool, awaitsDecision: Bool) {
        self.id = id
        self.project = project
        self.risky = risky
        self.awaitsDecision = awaitsDecision
    }
}

public enum VoiceOutcome: Equatable, Sendable {
    /// Say this, and do nothing else.
    case say(String)
    case decide(id: String, allow: Bool)
    /// Say this and wait for a yes; the caller holds the pending decision.
    case confirm(String, id: String, allow: Bool)
    case open(id: String)
    case status
    case hush
    case ignored
}

/// Turning what was said into what is done. Every rule about not guessing lives
/// here, in one pure function, because "it approved the wrong thing" is the
/// failure this whole app exists to prevent and it deserves tests rather than
/// confidence.
public enum VoiceCommand {
    /// A confirmation is a question asked out loud, not a dialog. It lapses, so
    /// a "yes" to someone else in the room half a minute later decides nothing.
    public static let confirmWindow: TimeInterval = 12

    public struct Pending: Equatable, Sendable {
        public let id: String
        public let allow: Bool
        public let asked: Date

        public init(id: String, allow: Bool, asked: Date) {
            self.id = id
            self.allow = allow
            self.asked = asked
        }

        public func isLive(at now: Date) -> Bool {
            now.timeIntervalSince(asked) < confirmWindow
        }
    }

    public static func outcome(
        for intent: Intent, targets: [SpokenTarget], selected: String? = nil,
        pending: Pending? = nil, now: Date = Date()
    ) -> VoiceOutcome {
        let live = pending.flatMap { $0.isLive(at: now) ? $0 : nil }

        switch intent {
        case .quiet:
            return .hush
        case .status:
            return .status
        case .yes:
            guard let live, targets.contains(where: { $0.id == live.id }) else { return .ignored }
            return .decide(id: live.id, allow: live.allow)
        case .no:
            guard live != nil else { return .ignored }
            return .say("Left it.")
        case .approve(let said):
            return decide(said, allow: true, targets: targets, selected: selected, now: now)
        case .deny(let said):
            return decide(said, allow: false, targets: targets, selected: selected, now: now)
        case .open(let said):
            switch pick(said, from: targets, selected: selected) {
            case .one(let target): return .open(id: target.id)
            case .none: return .say(nothingNamed(said, waiting: targets))
            case .many(let projects): return .say(whichOne(projects))
            }
        case .unknown:
            // Deliberately silent. A pet that says "sorry?" at every stray word
            // near its name is one nobody leaves listening.
            return .ignored
        }
    }

    private static func decide(_ said: String, allow: Bool, targets: [SpokenTarget],
                               selected: String?, now: Date) -> VoiceOutcome {
        let answerable = targets.filter(\.awaitsDecision)
        guard !answerable.isEmpty else { return .say("Nothing is waiting on a decision.") }
        switch pick(said, from: answerable, selected: selected) {
        case .none:
            return .say(nothingNamed(said, waiting: answerable))
        case .many(let projects):
            return .say(whichOne(projects))
        case .one(let target):
            let verb = allow ? "Approve" : "Deny"
            // Denying is the safe direction and goes straight through. Approving
            // something risky is asked again, out loud, naming what it is.
            guard allow, target.risky else { return .decide(id: target.id, allow: allow) }
            return .confirm("\(verb) the risky one in \(target.project)? Say yes.",
                            id: target.id, allow: allow)
        }
    }

    private enum Choice {
        case none
        case one(SpokenTarget)
        case many([String])
    }

    /// Named, or the one on screen, or the only one there is. Never a guess
    /// between two: being wrong here runs something nobody asked for.
    private static func pick(_ said: String, from targets: [SpokenTarget],
                             selected: String?) -> Choice {
        let named = Listening.match(said, against: targets.map(\.project))
        if !named.isEmpty {
            let matched = targets.filter { named.contains($0.project) }
            let projects = Set(matched.map(\.project))
            if matched.count == 1 { return .one(matched[0]) }
            return projects.count == 1 ? .many(Array(projects)) : .many(Array(projects).sorted())
        }
        // Nothing named at all: the one being looked at, else the only one.
        guard said.isEmpty || named.isEmpty else { return .none }
        if let selected, let target = targets.first(where: { $0.id == selected }) {
            return .one(target)
        }
        if targets.count == 1 { return .one(targets[0]) }
        return targets.isEmpty ? .none : .many(Array(Set(targets.map(\.project))).sorted())
    }

    private static func nothingNamed(_ said: String, waiting: [SpokenTarget]) -> String {
        let projects = Array(Set(waiting.map(\.project))).sorted()
        guard !projects.isEmpty else { return "Nothing is waiting." }
        return "I have nothing from that. Waiting: \(projects.joined(separator: ", "))."
    }

    private static func whichOne(_ projects: [String]) -> String {
        "Which one? \(projects.joined(separator: ", "))."
    }
}
