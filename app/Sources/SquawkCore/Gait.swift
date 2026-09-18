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
    /// Strides per second at full speed.
    public static let cadence: Double = 1.8

    /// `phase` counts strides, so 0.5 is mid stride and 1.0 is the next one.
    /// `effort` scales the whole thing, so an idle stand is the same maths with
    /// nothing turned up.
    public static func stride(phase: Double, effort: Double = 1) -> Stride {
        let turns = phase * 2 * .pi
        let swing = sin(turns)
        let opposite = sin(turns + .pi)

        return Stride(
            left: leg(at: turns, effort: effort),
            right: leg(at: turns + .pi, effort: effort),
            // The hips rise twice a stride, once over each foot.
            bob: (0.5 - 0.5 * cos(turns * 2)) * 0.06 * effort,
            sway: sin(turns) * 3.2 * effort,
            twist: opposite * 5 * effort,
            leftArm: opposite * 22 * effort,
            rightArm: swing * 22 * effort
        )
    }

    private static func leg(at turns: Double, effort: Double) -> LegPose {
        let swing = sin(turns)
        // The knee bends on the way through and straightens to plant, so it is
        // a half cycle against the hip's full one, and never bends backward.
        let bend = max(0, sin(turns - .pi / 2) + 1) / 2
        let hip = swing * hipSwing * effort
        let knee = bend * kneeBend * effort
        // The sole stays level with the ground through the planted half, and
        // the toe pushes off as the heel leaves it.
        let toeOff = max(0, sin(turns + .pi / 3)) * 14 * effort
        return LegPose(
            hip: hip,
            knee: knee,
            ankle: hip - knee + toeOff,
            // Weight is on the foot while it is behind and planted.
            load: max(0, -swing)
        )
    }

    /// How far along its walk something is, given how long it has been walking.
    public static func phase(at elapsed: TimeInterval, speed: Double = 1) -> Double {
        (elapsed * cadence * speed).truncatingRemainder(dividingBy: 1)
    }
}
