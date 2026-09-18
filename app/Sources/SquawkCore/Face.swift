import Foundation

/// What the dial's eyes are doing. Expression comes from eye shape alone, the
/// way a small monochrome companion display does it, so every case has to read
/// at a glance rather than through detail.
public enum FaceExpression: String, Sendable, CaseIterable {
    /// Nothing waiting. Open, level, blinking now and then.
    case calm
    /// Nothing waiting for a long while. Lids low.
    case sleepy
    /// A decision is waiting on you. Wide and level.
    case alert
    /// Several decisions are waiting. Wider still.
    case urgent
    /// A session wants you but there is nothing to decide, so it is a question
    /// rather than a demand.
    case curious
    /// You just approved something.
    case happy
    /// You just denied something.
    case cross
    /// A request went away on its own, because its agent did.
    case sad
    /// An idle flourish. Nothing happened; it is just alive.
    case wink
    /// The pending command looks like one to read twice.
    case wary
    /// Something arrived while it was asleep.
    case startled
    /// A backlog just cleared.
    case relieved
    /// Prodded well past the point of patience.
    case dizzy
    /// Idle a while, but not asleep yet.
    case bored

    /// Degrees the eye itself is rotated. Negative drops the inner edge, which
    /// is displeasure; positive drops the outer edge, which is worry. The eye
    /// carries the slant rather than a separate brow, which at this size would
    /// be two more strokes competing with the shape that already says it.
    public var eyeTilt: Double {
        switch self {
        case .cross: -24
        case .sad: 18
        case .wary: -12
        default: 0
        }
    }

    /// Brows only where the eye shape cannot carry it, which is delight.
    public var hasBrows: Bool { self == .happy || self == .relieved }
    /// Drawn as an upward arc rather than a filled eye.
    public var isArc: Bool { self == .happy || self == .relieved }

    /// Drawn as two crossed strokes, which is the one shape that reads as
    /// thoroughly done in.
    public var isCrossedOut: Bool { self == .dizzy }

    /// Looks away rather than at you, in units of eye width.
    public var gazeBias: Double { self == .bored ? -0.55 : 0 }

    /// Only the left eye closes on a wink; the asymmetry is the whole joke.
    public var winksLeftEye: Bool { self == .wink }

    /// Eye height as a share of the full open eye.
    public var openness: Double {
        switch self {
        case .calm: 1.0
        case .sleepy: 0.20
        case .alert: 1.12
        case .urgent: 1.2
        case .curious: 1.0
        case .happy: 1.0
        case .cross: 0.9
        case .sad: 0.82
        case .wink: 1.0
        case .wary: 0.62
        case .startled: 1.28
        case .relieved: 1.0
        case .dizzy: 1.0
        case .bored: 0.5
        }
    }

    /// Curious tips its head: one eye rides a little higher than the other.
    public var tilt: Double { self == .curious ? 0.16 : 0 }

    /// A mouth only appears where it adds something the eyes cannot say alone.
    /// Positive curves up, negative down, zero means no mouth at all.
    public var mouthCurve: Double {
        switch self {
        case .happy: 1.0
        case .sad: -0.8
        case .cross: -0.45
        case .curious: 0.25
        case .wink: 0.7
        case .relieved: 0.55
        case .startled: -0.15
        case .dizzy: -0.3
        default: 0
        }
    }

    public var hasMouth: Bool { mouthCurve != 0 }

    /// Delight gets the little triangular mouth; everything else gets a stroke.
    public var mouthIsTriangle: Bool { self == .happy }

    /// A reaction is shown briefly and then gives way to the resting face.
    public var isReaction: Bool {
        switch self {
        case .happy, .cross, .sad, .wink, .startled, .relieved, .dizzy: true
        default: false
        }
    }
}

/// What the dial is reacting to. Kept separate from the roster so the face is a
/// function of state rather than something each call site remembers to set.
public enum FaceEvent: Sendable, Equatable {
    case approved
    case denied
    case abandoned
    /// Something arrived while it was asleep.
    case startled
    /// A backlog cleared rather than a single request.
    case relieved
    /// You prodded it. `count` is how many times in quick succession, because
    /// being poked once is play and being poked six times is pestering.
    case poked(count: Int)
}

/// How a poke is taken, which changes if you keep doing it.
public enum Poke {
    /// Pokes closer together than this count as the same bout.
    public static let bout: TimeInterval = 2.5
    /// Past this many in one bout it stops being funny.
    public static let patience = 4

    /// Keep going past cross and it gives up entirely.
    public static let limit = 8

    public static func reaction(to count: Int) -> FaceExpression {
        if count >= limit { return .dizzy }
        if count >= patience { return .cross }
        return count.isMultiple(of: 2) ? .happy : .wink
    }
}

/// Picks the expression. Pure, because the interesting part is the rules and
/// they are worth pinning down.
public enum FaceMood {
    /// How long a reaction holds before the resting face returns.
    public static let reactionDuration: TimeInterval = 1.1
    /// How long with nothing waiting before it starts looking about.
    public static let boredAfter: TimeInterval = 35
    /// How long with nothing waiting before the eyes get heavy.
    public static let sleepAfter: TimeInterval = 90

    public static func expression(
        waiting: Int,
        awaitingDecision: Bool,
        lastEvent: FaceEvent?,
        eventAge: TimeInterval,
        idleFor: TimeInterval,
        risky: Bool = false
    ) -> FaceExpression {
        // A reaction outranks everything, briefly, so an answer is acknowledged.
        if let lastEvent, eventAge < reactionDuration {
            switch lastEvent {
            case .approved: return .happy
            case .denied: return .cross
            case .abandoned: return .sad
            case .poked(let count): return Poke.reaction(to: count)
            case .startled: return .startled
            case .relieved: return .relieved
            }
        }
        guard waiting > 0 else {
            if idleFor >= sleepAfter { return .sleepy }
            if idleFor >= boredAfter { return .bored }
            return .calm
        }
        guard awaitingDecision else { return .curious }
        // A command worth reading twice outranks how many are queued.
        if risky { return .wary }
        return waiting > 1 ? .urgent : .alert
    }
}
