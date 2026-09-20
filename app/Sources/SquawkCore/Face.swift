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
    /// Music is playing. Not the bright delight of an answer accepted but the
    /// look of somebody enjoying a track: eyes wide and level, a broad smile,
    /// and a colour that drifts round the wheel while it listens. The head tilt
    /// went: at this size an uneven pair of eyes reads as a fault rather than
    /// as a head on one side.
    case grooving
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
    /// Ignored for long enough that it wants you to look up. Doubles as a break
    /// reminder: the nudge is the point, not the mood.
    case restless
    /// Nothing is waiting on you, but the agents are busy. Eyes narrowed and
    /// level: the look of someone concentrating on something, which is what
    /// the pet used to sleep through.
    case working

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

    /// Whether it should put itself in front of you rather than wait to be
    /// looked at. Only the break nudge does.
    public var demandsAttention: Bool { self == .restless }

    /// Colour carries the feeling the shape cannot. It fades in and back out
    /// with everything else, so nothing snaps between hues.
    public var tint: FaceTint {
        switch self {
        case .cross: .irritation
        case .dizzy: .anger
        case .sad: .sorrow
        case .wary: .caution
        default: .brand
        }
    }

    /// Only the left eye closes on a wink; the asymmetry is the whole joke.
    public var winksLeftEye: Bool { self == .wink }

    /// Eye height as a share of the full open eye.
    public var openness: Double {
        switch self {
        // Resting is wide eyed. A companion at rest looking back at you with
        // big open eyes is the whole charm of the thing; a level 1.0 made it
        // look merely switched on, and left nothing between it and the faces
        // that are supposed to be reacting.
        case .calm: 1.16
        case .sleepy: 0.20
        case .alert: 1.24
        case .urgent: 1.32
        case .curious: 1.0
        case .happy: 1.0
        // Wide and alive. Closed arcs with an open mouth were meant to read as
        // singing with your eyes shut and read as asleep with your mouth open.
        case .grooving: 1.20
        case .cross: 0.9
        case .sad: 0.82
        case .wink: 1.0
        case .wary: 0.62
        case .startled: 1.38
        case .relieved: 1.0
        case .dizzy: 1.0
        case .bored: 0.5
        case .restless: 1.22
        // Narrowed, not drooping. Below about 0.8 it starts reading as bored,
        // which is the exact state this exists to stop it looking like.
        case .working: 0.86
        }
    }

    /// Curious tips its head: one eye rides a little higher than the other.
    /// One eye rides higher than the other, which is a head on one side.
    public var tilt: Double {
        switch self {
        case .curious: 0.16
        default: 0
        }
    }

    /// A mouth only appears where it adds something the eyes cannot say alone.
    /// Positive curves up, negative down, zero means no mouth at all.
    public var mouthCurve: Double {
        switch self {
        case .happy: 1.0
        // A broad smile. An open mouth was tried and, with the eyes, read as a
        // yawn rather than as singing.
        case .grooving: 0.85
        case .sad: -0.8
        case .cross: -0.45
        case .curious: 0.25
        case .wink: 0.7
        case .relieved: 0.55
        case .startled: -0.15
        case .dizzy: -0.3
        case .restless: 0.4
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

/// An eye colour, as plain components so core stays free of AppKit.
public struct FaceTint: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// From the brand tokens, so the face and the arcs agree.
    public static let brand = FaceTint(0x67 / 255, 0xE8 / 255, 0xD0 / 255)

    /// A point on the colour wheel, for eyes that drift while music plays.
    /// Kept bright and well saturated: the eyes are the only lit thing on the
    /// pet, and a muddy hue reads as a fault rather than a mood.
    public static func hue(_ position: Double) -> FaceTint {
        let turn = (position.truncatingRemainder(dividingBy: 1) + 1)
            .truncatingRemainder(dividingBy: 1)
        let sector = turn * 6
        let index = Int(sector) % 6
        let rise = sector - Double(Int(sector))
        let low = 0.42, high = 1.0
        let up = low + (high - low) * rise
        let down = high - (high - low) * rise
        switch index {
        case 0: return FaceTint(high, up, low)
        case 1: return FaceTint(down, high, low)
        case 2: return FaceTint(low, high, up)
        case 3: return FaceTint(low, down, high)
        case 4: return FaceTint(up, low, high)
        default: return FaceTint(high, low, down)
        }
    }

    /// A full turn of the wheel, in seconds. Slow enough that you notice it
    /// has changed rather than watching it change.
    public static let hueCycle: Double = 26
    /// How often the drifting eye is re-aimed, in seconds. The animator eases
    /// between aims, so a few a second look continuous and cost a fraction.
    public static let hueStep: Double = 0.3
    public static let irritation = FaceTint(0xFF / 255, 0x8A / 255, 0x3D / 255)
    public static let anger = FaceTint(0xFF / 255, 0x5B / 255, 0x5B / 255)
    public static let sorrow = FaceTint(0x4F / 255, 0xC7 / 255, 0xFF / 255)
    public static let caution = FaceTint(0xF6 / 255, 0xB9 / 255, 0x4E / 255)
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
    /// You prodded it. The face is chosen when the poke happens, not when it is
    /// rendered, so a random pick is not re-rolled on every frame.
    case poked(FaceExpression)
}

/// How a poke is taken, which changes if you keep doing it.
public enum Poke {
    /// Pokes closer together than this count as the same bout.
    public static let bout: TimeInterval = 2.5
    /// Past this many in one bout it stops being funny.
    public static let patience = 4

    /// Keep going past cross and it gives up entirely.
    public static let limit = 8

    /// What a friendly prod can produce. Picked at random so prodding it twice
    /// is not the same animation twice, which is what made it feel scripted.
    public static let playful: [FaceExpression] = [
        .wink, .happy, .curious, .startled, .relieved,
    ]

    /// The candidates for a given prod, never repeating the one just shown.
    public static func options(avoiding previous: FaceExpression?) -> [FaceExpression] {
        let rest = playful.filter { $0 != previous }
        return rest.isEmpty ? playful : rest
    }

    /// Escalation stays deliberate: past patience it is cross, past the limit
    /// it gives up. Only the friendly phase is random.
    public static func reaction(to count: Int, avoiding previous: FaceExpression? = nil) -> FaceExpression {
        if count >= limit { return .dizzy }
        if count >= patience { return .cross }
        return options(avoiding: previous).randomElement() ?? .wink
    }
}

/// Picks the expression. Pure, because the interesting part is the rules and
/// they are worth pinning down.
public enum FaceMood {
    /// How long a reaction holds before the resting face returns.
    public static let reactionDuration: TimeInterval = 1.1
    /// How long with nothing waiting before it starts looking about.
    public static let boredAfter: TimeInterval = 150
    /// How long with nothing waiting before the eyes get heavy. Its resting
    /// face should be the awake one: at ninety seconds it spent most of the
    /// day half shut, which reads as a pet that is bored of you rather than
    /// one that is waiting with you.
    public static let sleepAfter: TimeInterval = 300

    public static func expression(
        waiting: Int,
        awaitingDecision: Bool,
        lastEvent: FaceEvent?,
        eventAge: TimeInterval,
        idleFor: TimeInterval,
        risky: Bool = false,
        working: Bool = false
    ) -> FaceExpression {
        // A reaction outranks everything, briefly, so an answer is acknowledged.
        if let lastEvent, eventAge < reactionDuration {
            switch lastEvent {
            case .approved: return .happy
            case .denied: return .cross
            case .abandoned: return .sad
            case .poked(let face): return face
            case .startled: return .startled
            case .relieved: return .relieved
            }
        }
        guard waiting > 0 else {
            // Busy agents outrank the idle clock entirely. Judging "idle" by
            // the dial alone is what let the pet sleep through twenty minutes
            // of auto approved work, and a sleeping pet over a working machine
            // is worse than no pet: it is wrong about the one thing it is for.
            if working { return .working }
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
