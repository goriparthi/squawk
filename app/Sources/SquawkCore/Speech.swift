import Foundation

/// Something the pet is saying, and until when. Fortunes, the now playing
/// card, wellness prompts and the refusal shared one timer and four closures,
/// and whichever expired last cleared the others.
public struct Speech: Equatable, Sendable {
    /// Lowest to highest. A higher kind takes the bubble at once; a lower one
    /// is refused while the higher is still up.
    public enum Kind: Int, Comparable, Sendable {
        /// Hello. The least important thing it ever says, and the first to
        /// give way to anything at all.
        case greeting, nowPlaying, fortune, wellness, reply, refusal
        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let kind: Kind
    public let face: FaceExpression
    public let until: Date
    /// Whether the body holds still for it: a sway over a refusal aims it elsewhere.
    public let holdsStill: Bool

    public init(kind: Kind, face: FaceExpression, until: Date, holdsStill: Bool = false) {
        self.kind = kind
        self.face = face
        self.until = until
        self.holdsStill = holdsStill
    }

    /// Whether something waiting outranks it. Looking after you does not
    /// yield, and neither does an answer to a question you just asked.
    public var yieldsToWork: Bool { kind != .wellness && kind != .reply }
}

/// The one slot the pet speaks from.
public struct Speaking: Equatable, Sendable {
    public private(set) var current: Speech?

    public init() {}

    /// Takes the slot unless something higher is still being said. Says whether it did.
    @discardableResult
    public mutating func say(_ speech: Speech, at now: Date) -> Bool {
        if let current, now < current.until, current.kind > speech.kind { return false }
        current = speech
        return true
    }

    /// What is being said right now; an expired speech is dropped here.
    public mutating func speech(at now: Date) -> Speech? {
        if let current, now >= current.until { self.current = nil }
        return current
    }

    /// Stops one kind, or everything.
    public mutating func stop(_ kind: Speech.Kind? = nil) {
        guard let kind else { return current = nil }
        if current?.kind == kind { current = nil }
    }
}
