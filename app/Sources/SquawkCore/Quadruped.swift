import Foundation

/// A four legged walk. Deliberately expressed as the same `Pose3D` a biped
/// uses: the front legs take the arm channels and the hind legs the leg ones,
/// so the springs, the moods and the dance all work on a dog without knowing
/// there is one. If that mapping had not held, a quadruped would have needed
/// its own pipeline.
public enum Trot {
    /// Diagonal pairs move together, which is what a trot is and what stops a
    /// four legged walk reading as a pantomime horse.
    ///
    /// Front left is in phase with hind right, front right with hind left.
    public static func pose(phase: Double, effort: Double = 1) -> Pose3D {
        let turns = phase * 2 * .pi
        var pose = Pose3D()

        let frontLeft = limb(at: turns, effort: effort, front: true)
        let frontRight = limb(at: turns + .pi, effort: effort, front: true)
        let hindLeft = limb(at: turns + .pi, effort: effort, front: false)
        let hindRight = limb(at: turns, effort: effort, front: false)

        pose.leftShoulder = frontLeft.upper
        pose.leftElbow = frontLeft.lower
        pose.rightShoulder = frontRight.upper
        pose.rightElbow = frontRight.lower

        pose.leftHip = hindLeft.upper
        pose.leftKnee = hindLeft.lower
        pose.leftAnkle = hindLeft.foot
        pose.rightHip = hindRight.upper
        pose.rightKnee = hindRight.lower
        pose.rightAnkle = hindRight.foot

        // The back rises twice a stride, once over each diagonal pair, and
        // rolls a little onto whichever pair is carrying.
        pose.bob = (0.5 - 0.5 * cos(turns * 2)) * 0.045 * effort
        pose.sway = sin(turns) * 2.2 * effort
        // The spine flexes with the pairs rather than the body staying rigid.
        pose.twist = sin(turns) * 3.5 * effort
        // The head stays level while the body works underneath it, which is the
        // single thing that makes a walking quadruped look alive.
        pose.headPitch = -pose.bob * 60 * effort
        pose.headYaw = -pose.twist * 0.5
        pose.lean = 1.5 * effort
        return pose
    }

    /// Standing square, with the small bend every animal keeps in its legs.
    /// Defined as the walk with the effort turned off rather than written out
    /// again: two definitions of standing drifted apart in sign, and the dog
    /// jumped between standing and walking.
    public static func standing() -> Pose3D {
        pose(phase: 0, effort: 0)
    }

    /// How far the upper limb swings either side of its stance angle.
    public static let reach: Double = 22
    /// Front legs fold forward at the elbow, hind legs fold back at the hock.
    /// Getting this backward is what makes a robot dog look like a table.
    public static let frontStance: Double = 12
    public static let hindStance: Double = 16

    private struct Limb {
        let upper: Double
        let lower: Double
        let foot: Double
    }

    private static func limb(at turns: Double, effort: Double, front: Bool) -> Limb {
        let swing = sin(turns)
        // The knee folds to lift the foot clear on the way through, and comes
        // out straight to plant. Half a cycle against the hip's full one.
        let lift = max(0, sin(turns - .pi / 2) + 1) / 2
        let stance = front ? frontStance : hindStance
        let upper = stance + swing * reach * effort
        // A front leg's joint closes the other way from a hind leg's.
        let fold = lift * (front ? 34.0 : 40.0) * effort
        return Limb(
            upper: upper,
            lower: front ? -(stance * 1.6 + fold) : (stance * 1.7 + fold),
            foot: front ? 0 : -(stance * 0.8) - fold * 0.4
        )
    }
}
