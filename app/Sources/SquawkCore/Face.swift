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

    /// Degrees the eye itself is rotated. Negative drops the inner edge, which
    /// is displeasure; positive drops the outer edge, which is worry. The eye
    /// carries the slant rather than a separate brow, which at this size would
    /// be two more strokes competing with the shape that already says it.
    public var eyeTilt: Double {
        switch self {
        case .cross: -24
        case .sad: 18
        default: 0
        }
    }

    /// Brows only where the eye shape cannot carry it, which is delight.
    public var hasBrows: Bool { self == .happy }
    /// Drawn as an upward arc rather than a filled eye.
    public var isArc: Bool { self == .happy }

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
        default: 0
        }
    }

    public var hasMouth: Bool { mouthCurve != 0 }

    /// Delight gets the little triangular mouth; everything else gets a stroke.
    public var mouthIsTriangle: Bool { self == .happy }

    /// A reaction is shown briefly and then gives way to the resting face.
    public var isReaction: Bool {
        switch self {
        case .happy, .cross, .sad, .wink: true
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

    public static func reaction(to count: Int) -> FaceExpression {
        if count >= patience { return .cross }
        return count.isMultiple(of: 2) ? .happy : .wink
    }
}

/// Picks the expression. Pure, because the interesting part is the rules and
/// they are worth pinning down.
public enum FaceMood {
    /// How long a reaction holds before the resting face returns.
    public static let reactionDuration: TimeInterval = 1.1
    /// How long with nothing waiting before the eyes get heavy.
    public static let sleepAfter: TimeInterval = 90

    public static func expression(
        waiting: Int,
        awaitingDecision: Bool,
        lastEvent: FaceEvent?,
        eventAge: TimeInterval,
        idleFor: TimeInterval
    ) -> FaceExpression {
        // A reaction outranks everything, briefly, so an answer is acknowledged.
        if let lastEvent, eventAge < reactionDuration {
            switch lastEvent {
            case .approved: return .happy
            case .denied: return .cross
            case .abandoned: return .sad
            case .poked(let count): return Poke.reaction(to: count)
            }
        }
        guard waiting > 0 else {
            return idleFor >= sleepAfter ? .sleepy : .calm
        }
        guard awaitingDecision else { return .curious }
        return waiting > 1 ? .urgent : .alert
    }
}
