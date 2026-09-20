import Foundation

/// One ambient thing the pet does with itself when nothing is happening.
///
/// The breath and the wandering head underneath never stop; these ride on top
/// of them. Nothing here means anything, which is the point: a move that meant
/// something would be a notification, and the pet already has those.
public enum IdleMove: String, Sendable, CaseIterable, Equatable {
    /// Turns its head toward the pointer and watches it for a moment.
    case watchCursor
    /// Looks off to one side, as though something moved there.
    case lookAround
    /// Rolls its head over and back.
    case rollHead
    /// Looks up at the menu bar, where its own icon lives.
    case glanceUp
    /// Arms up and over, a long stretch.
    case stretch
    /// Lets its eyes fall shut for a second without actually sleeping.
    case doze

    /// How often it should come up relative to the others, before cooldowns and
    /// the variety memory have had their say. Watching the pointer leads
    /// because it is the only one that reads as the pet noticing you.
    public var weight: Double {
        switch self {
        case .watchCursor: 3.0
        case .lookAround: 2.5
        case .rollHead: 2.0
        case .glanceUp: 1.5
        case .stretch: 1.0
        case .doze: 1.0
        }
    }

    /// How long before this one may come up again. The big, legible ones wait
    /// longest: a stretch twice in a minute is a tic, not a stretch.
    public var cooldown: TimeInterval {
        switch self {
        case .watchCursor: 45
        case .lookAround: 60
        case .rollHead: 90
        case .glanceUp: 120
        case .doze: 180
        case .stretch: 240
        }
    }

    /// How long it takes to perform.
    public var duration: TimeInterval {
        switch self {
        case .watchCursor: 2.6
        case .lookAround: 1.8
        case .rollHead: 2.0
        case .glanceUp: 1.6
        case .doze: 2.2
        case .stretch: 3.0
        }
    }
}

/// Picks what the pet does with itself, and remembers enough not to repeat.
///
/// One sine driven sway is a screensaver: you stop seeing it inside a day. A
/// catalogue is only an improvement if it does not loop, and weight alone does
/// not get there, because the heaviest entry can still come up three times
/// running. So every move has its own cooldown, and the last few are pushed
/// down rather than merely being less likely.
///
/// The roll is handed in rather than drawn here, so the choice is a pure
/// function of state and the tests are not flaky.
public struct Idler: Sendable {
    /// How many are remembered, and what their weight is cut to.
    public static let remembers = 5
    public static let recentShare = 0.25
    /// The gap between one move ending and the next being considered. Anything
    /// shorter is fidgeting rather than idling.
    public static let restBetween: TimeInterval = 20

    private var lastPlayed: [IdleMove: Date] = [:]
    private var recent: [IdleMove] = []
    private var freeAt: Date?

    public init() {}

    /// What each move is worth right now. Zero means it is on cooldown.
    public func weights(at now: Date) -> [(move: IdleMove, weight: Double)] {
        IdleMove.allCases.map { move in
            guard let played = lastPlayed[move],
                  now.timeIntervalSince(played) < move.cooldown
            else {
                let cut = recent.contains(move) ? Self.recentShare : 1
                return (move, move.weight * cut)
            }
            return (move, 0)
        }
    }

    /// The next move, or nil when it is not time or everything is resting.
    ///
    /// `roll` is a fraction of the way through the total weight, so a caller
    /// passes `Double.random(in: 0..<1)` and a test passes whatever it means.
    public mutating func next(at now: Date, roll: Double) -> IdleMove? {
        // Seeded on the first ask rather than firing at once: going quiet and
        // immediately performing reads as a twitch, not as settling in.
        guard let freeAt else {
            self.freeAt = now.addingTimeInterval(Self.restBetween)
            return nil
        }
        guard now >= freeAt else { return nil }

        let live = weights(at: now).filter { $0.weight > 0 }
        // Everything on cooldown is a perfectly good answer: the pet stands
        // there and breathes, which is what it did before any of this.
        guard !live.isEmpty else { return nil }

        let total = live.reduce(0) { $0 + $1.weight }
        var cursor = min(max(roll, 0), 0.999_999) * total
        for (move, weight) in live {
            cursor -= weight
            guard cursor < 0 else { continue }
            began(move, at: now)
            return move
        }
        // Floating point drift at the very top of the range; the last live
        // entry is the one the cursor was inside.
        let move = live[live.count - 1].move
        began(move, at: now)
        return move
    }

    /// Interrupted, because something started happening. Whatever was being
    /// performed is over, and the next one waits its turn like any other.
    public mutating func interrupt(at now: Date) {
        freeAt = now.addingTimeInterval(Self.restBetween)
    }

    private mutating func began(_ move: IdleMove, at now: Date) {
        lastPlayed[move] = now
        recent.append(move)
        if recent.count > Self.remembers { recent.removeFirst(recent.count - Self.remembers) }
        freeAt = now.addingTimeInterval(move.duration + Self.restBetween)
    }
}

/// What a move looks like, as offsets laid over the breath rather than a pose
/// replacing it. The pet keeps breathing through a glance, which is the whole
/// difference between a creature looking at something and a puppet being posed.
///
/// Here rather than in the view because the shapes are the interesting part,
/// and a shape that overshoots or fails to return is a bug worth a test.
public enum IdleShape {
    /// Eased in and out over the move's own length, peaking in the middle and
    /// ending exactly where it started. Anything that does not return to zero
    /// leaves the pet permanently tilted.
    public static func arc(_ progress: Double) -> Double {
        guard progress > 0, progress < 1 else { return 0 }
        return sin(progress * .pi)
    }

    /// Reaches and holds, rather than peaking and leaving at once: watching
    /// something is mostly the holding.
    public static func hold(_ progress: Double, rise: Double = 0.25) -> Double {
        guard progress > 0, progress < 1 else { return 0 }
        if progress < rise { return sin(progress / rise * .pi / 2) }
        if progress > 1 - rise { return sin((1 - progress) / rise * .pi / 2) }
        return 1
    }

    /// The offsets a move adds, at a fraction of the way through it.
    /// `toward` is where the pointer is, left to right, as -1 to 1.
    public static func apply(_ move: IdleMove, progress: Double, toward: Double = 0,
                             to pose: inout Pose3D) {
        switch move {
        case .watchCursor:
            // Turns and stays turned, so it reads as watching rather than as a
            // twitch in the pointer's direction.
            let amount = hold(progress)
            pose.headYaw += amount * 26 * max(-1, min(1, toward))
            pose.headPitch += amount * 4
        case .lookAround:
            let amount = arc(progress)
            pose.headYaw += amount * 30
            pose.twist += amount * 5
        case .rollHead:
            pose.headRoll += arc(progress) * 16
            pose.headPitch += arc(progress) * 3
        case .glanceUp:
            // Up at the menu bar, where its own icon lives.
            pose.headPitch -= hold(progress) * 20
        case .stretch:
            let amount = arc(progress)
            pose.leftShoulder += amount * 74
            pose.rightShoulder += amount * 66
            pose.leftElbow += amount * 28
            pose.rightElbow += amount * 22
            pose.lean -= amount * 5
            pose.bob += amount * 0.02
        case .doze:
            // A nod, not a sleep: the eyes are the face's business.
            let amount = hold(progress, rise: 0.4)
            pose.headPitch += amount * 12
            pose.headRoll += amount * 5
        }
    }
}
