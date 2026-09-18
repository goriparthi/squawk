import Foundation

/// One leg at one moment of a stride, in degrees. Positive hip swings the leg
/// forward, positive knee bends it back, which is the only way a knee bends.
public struct LegPose: Sendable, Equatable {
    public let hip: Double
    public let knee: Double
    /// Degrees at the ankle. Without one the foot swings with the shin and the
    /// pet walks on its toes, which is the difference between a stride and a
    /// pair of pendulums.
    public let ankle: Double
    /// How much of the body's weight is on this foot, 0 to 1. The shadow and
    /// the bob both read from it, so they cannot disagree about which foot is
    /// down.
    public let load: Double

    public init(hip: Double, knee: Double, ankle: Double = 0, load: Double) {
        self.hip = hip
        self.knee = knee
        self.ankle = ankle
        self.load = load
    }
}

/// Everything a stride does to the body at one moment.
public struct Stride: Sendable, Equatable {
    public let left: LegPose
    public let right: LegPose
    /// How far the hips rise and fall, as a share of leg length.
    public let bob: Double
    /// Degrees the body rocks side to side over the planted foot.
    public let sway: Double
    /// Degrees the shoulders counter rotate against the hips.
    public let twist: Double
    /// The arms swing opposite their own leg, which is what stops a walk
    /// reading as a march.
    public let leftArm: Double
    public let rightArm: Double
}

/// A walk cycle, as maths rather than keyframes. Everything is a function of
/// one phase, so speeding the walk up cannot desynchronise the parts of it.
public enum Gait {
    /// Degrees the hip swings either side of straight down at full speed.
    public static let hipSwing: Double = 26
    /// A knee that never straightens looks like a crouch; one that never bends
    /// looks like stilts.
    public static let kneeBend: Double = 34
    public static let armSwing: Double = 20
    /// How far behind its leg an arm runs, as a share of a stride.
    public static let armLag: Double = 0.07
    /// Strides per second. A person walking unhurried takes about one full
    /// stride a second, two steps; anything much above that is a scurry.
    public static let cadence: Double = 0.82

    /// The pose this stride puts the whole body in, ready to be sprung toward.
    /// The head counters the shoulders so it stays pointed where the pet is
    /// going, which is what people do and what makes a walk look intentional.
    public static func pose(phase: Double, effort: Double = 1) -> Pose3D {
        let moment = stride(phase: phase, effort: effort)
        var pose = Pose3D()
        pose.leftShoulder = 12 + moment.leftArm
        pose.rightShoulder = 12 + moment.rightArm
        pose.leftElbow = -14 - max(0, moment.leftArm) * 0.5
        pose.rightElbow = -14 - max(0, moment.rightArm) * 0.5
        pose.leftHip = moment.left.hip
        pose.leftKnee = moment.left.knee
        pose.leftAnkle = moment.left.ankle
        pose.rightHip = moment.right.hip
        pose.rightKnee = moment.right.knee
        pose.rightAnkle = moment.right.ankle
        pose.bob = moment.bob
        pose.sway = moment.sway
        pose.twist = moment.twist
        // Leaning into the walk, the way weight goes before feet do.
        pose.lean = 3.5 * effort
        pose.headYaw = -moment.twist * 0.7
        pose.headRoll = -moment.sway * 0.45
        return pose
    }

    /// `phase` counts strides, so 0.5 is mid stride and 1.0 is the next one.
    /// `effort` scales the whole thing, so an idle stand is the same maths with
    /// nothing turned up.
    public static func stride(phase: Double, effort: Double = 1) -> Stride {
        let turns = phase * 2 * .pi
        let opposite = sin(turns + .pi)

        // An arm is not driven, it is dragged: it reaches the end of its swing
        // a little after the leg it answers does. Without the lag both ends of
        // the body turn at once and it reads as clockwork.
        let lag = armLag * 2 * .pi
        return Stride(
            left: leg(at: turns, effort: effort),
            right: leg(at: turns + .pi, effort: effort),
            // The hips rise twice a stride, once over each foot.
            bob: (0.5 - 0.5 * cos(turns * 2)) * 0.055 * effort,
            sway: sin(turns) * 3.6 * effort,
            twist: opposite * 5.5 * effort,
            leftArm: sin(turns + .pi - lag) * armSwing * effort,
            rightArm: sin(turns - lag) * armSwing * effort
        )
    }

    private static func leg(at turns: Double, effort: Double) -> LegPose {
        let swing = sin(turns)
        // The knee bends to clear the ground on the way through and straightens
        // to plant, so it is a half cycle against the hip's full one, and it
        // never bends backward.
        let clearance = max(0, sin(turns - .pi / 2) + 1) / 2
        // A second, much smaller bend just after the heel lands. This is what a
        // walk has and a marionette does not: the leg takes the weight by
        // giving a little rather than by locking straight.
        let load = max(0, sin(turns * 2 + .pi * 0.85))
        let stanceFlex = load * max(0, -swing) * stanceKneeFlex

        let hip = swing * hipSwing * effort
        let knee = (clearance * kneeBend + stanceFlex) * effort
        // The sole stays level with the ground through the planted half, and
        // the toe pushes off as the heel leaves it.
        let toeOff = max(0, sin(turns + .pi / 3)) * toeOffAngle * effort
        // A heel leads into the plant rather than the foot landing flat.
        let heelStrike = max(0, sin(turns + .pi / 2)) * heelStrikeAngle * effort
        return LegPose(
            hip: hip,
            knee: knee,
            ankle: hip - knee + toeOff - heelStrike,
            // Weight is on the foot while it is behind and planted.
            load: max(0, -swing)
        )
    }

    /// How far the knee gives as the weight lands on it.
    public static let stanceKneeFlex: Double = 9
    public static let toeOffAngle: Double = 16
    public static let heelStrikeAngle: Double = 7

    /// How far along its walk something is, given how long it has been walking.
    public static func phase(at elapsed: TimeInterval, speed: Double = 1) -> Double {
        (elapsed * cadence * speed).truncatingRemainder(dividingBy: 1)
    }
}
