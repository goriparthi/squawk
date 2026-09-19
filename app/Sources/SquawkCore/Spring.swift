import Foundation

/// A critically damped spring, which is what makes a limb arrive somewhere
/// rather than teleport. Everything the companion does is routed through one,
/// so a joint carries momentum: it leads into a move and settles out of it
/// instead of snapping between keyframes.
///
/// Semi implicit Euler, which stays stable at the long frame a stall produces
/// where an explicit step would throw the limb across the screen.
public struct Spring: Sendable, Equatable {
    public var value: Double
    public var velocity: Double = 0

    /// Seconds to settle. Smaller is stiffer; a limb tracking a stride needs to
    /// be stiff or the walk turns to jelly.
    public var response: Double
    /// 1 is critically damped, below 1 overshoots and comes back, which is what
    /// reads as follow through on a hand or a head.
    public var damping: Double

    public init(_ value: Double = 0, response: Double = 0.12, damping: Double = 1) {
        self.value = value
        self.response = response
        self.damping = damping
    }

    @discardableResult
    public mutating func step(toward target: Double, dt: Double) -> Double {
        guard dt > 0 else { return value }
        // Integrated in slices short against the spring's own period. A fixed
        // 1/90 s was on the edge for the stiffest joints: at 120fps a frame was
        // one shorter step, at 30fps it was three full slices, and the ankles
        // grew to infinity over a minute of grooving and took the feet with them.
        let frequency = 2 * Double.pi / max(0.0001, response)
        let slice = min(1.0 / 90, max(0.0001, response) / 24)
        var remaining = min(dt, 0.25)
        while remaining > 0 {
            let step = Swift.min(slice, remaining)
            remaining -= step
            let acceleration = frequency * frequency * (target - value)
                - 2 * damping * frequency * velocity
            velocity += acceleration * step
            value += velocity * step
        }
        return value
    }

    /// Drops it where it stands, for a cut rather than a move.
    public mutating func reset(to target: Double) {
        value = target
        velocity = 0
    }
}

/// Every angle the modelled companion has, in degrees, as one value. Moods,
/// the walk and the dance all produce one of these, so they can be sprung
/// toward and blended into each other rather than each driving the joints
/// directly and fighting over them.
public struct Pose3D: Sendable, Equatable {
    public var leftShoulder: Double = 14
    public var leftElbow: Double = 0
    public var rightShoulder: Double = 14
    public var rightElbow: Double = 0
    public var leftHip: Double = 0
    public var leftKnee: Double = 0
    public var leftAnkle: Double = 0
    public var rightHip: Double = 0
    public var rightKnee: Double = 0
    public var rightAnkle: Double = 0
    /// Forward tip of the whole body.
    public var lean: Double = 0
    /// Roll over the planted foot.
    public var sway: Double = 0
    /// Shoulders against hips.
    public var twist: Double = 0
    public var spin: Double = 0
    /// Rise and fall of the hips, in scene units rather than degrees.
    public var bob: Double = 0
    /// Where the pet is along its walk, in scene units.
    public var travel: Double = 0
    public var headYaw: Double = 0
    public var headRoll: Double = 0
    public var headPitch: Double = 0
    /// Degrees the right arm swings forward, out of the plane the arms
    /// normally move in. Pointing at someone is the one gesture that needs it,
    /// and it is the one gesture worth the extra channel.
    public var point: Double = 0
    public var leftGrip: Grip = .loose
    public var rightGrip: Grip = .loose

    public init() {}
}

/// Springs every channel of a pose toward a target. Limbs are stiff enough to
/// track a stride; the head and the lean are looser, because a head that
/// tracked exactly would look bolted on.
public struct PoseSpring: Sendable {
    private var joints: [Spring]
    private var grips: (left: Grip, right: Grip) = (.loose, .loose)

    /// Response per channel, in the order `channels` reads them.
    private static let responses: [Double] = [
        0.10, 0.12, 0.10, 0.12,        // arms
        0.09, 0.09, 0.08,              // left leg
        0.09, 0.09, 0.08,              // right leg
        0.20, 0.16, 0.18, 0.22,        // lean, sway, twist, spin
        0.11, 0.13,                    // bob, travel
        0.26, 0.24, 0.26,              // head
        0.11,                          // point
    ]

    /// A hand or a head that overshoots a little and comes back reads as having
    /// weight. A knee that does reads as broken.
    private static let dampings: [Double] = [
        0.78, 0.72, 0.78, 0.72,
        1.0, 1.0, 0.95,
        1.0, 1.0, 0.95,
        0.82, 0.9, 0.85, 0.8,
        1.0, 1.0,
        0.7, 0.68, 0.72,
        0.74,
    ]

    public init(_ pose: Pose3D = Pose3D()) {
        let start = Self.channels(of: pose)
        joints = start.enumerated().map { index, value in
            Spring(value, response: Self.responses[index], damping: Self.dampings[index])
        }
        grips = (pose.leftGrip, pose.rightGrip)
    }

    public mutating func step(toward target: Pose3D, dt: Double) -> Pose3D {
        let wanted = Self.channels(of: target)
        for index in joints.indices {
            joints[index].step(toward: wanted[index], dt: dt)
        }
        // A hand changes shape rather than angle, so it cuts rather than springs.
        grips = (target.leftGrip, target.rightGrip)
        return Self.pose(from: joints.map(\.value), grips: grips)
    }

    /// Brings a spin back inside one turn without moving the model. The dance
    /// ends on a full 360, and springing that back to zero unwound the whole
    /// turn in reverse, leaving the pet standing at an angle on the way.
    public mutating func unwindSpin() {
        let turns = (joints[13].value / 360).rounded()
        joints[13].value -= turns * 360
    }

    /// Cuts straight to a pose, for the moment something appears rather than
    /// moves.
    public mutating func reset(to pose: Pose3D) {
        let values = Self.channels(of: pose)
        for index in joints.indices { joints[index].reset(to: values[index]) }
        grips = (pose.leftGrip, pose.rightGrip)
    }

    private static func channels(of pose: Pose3D) -> [Double] {
        [pose.leftShoulder, pose.leftElbow, pose.rightShoulder, pose.rightElbow,
         pose.leftHip, pose.leftKnee, pose.leftAnkle,
         pose.rightHip, pose.rightKnee, pose.rightAnkle,
         pose.lean, pose.sway, pose.twist, pose.spin,
         pose.bob, pose.travel,
         pose.headYaw, pose.headRoll, pose.headPitch, pose.point]
    }

    private static func pose(from values: [Double], grips: (left: Grip, right: Grip)) -> Pose3D {
        var pose = Pose3D()
        pose.leftShoulder = values[0]
        pose.leftElbow = values[1]
        pose.rightShoulder = values[2]
        pose.rightElbow = values[3]
        pose.leftHip = values[4]
        pose.leftKnee = values[5]
        pose.leftAnkle = values[6]
        pose.rightHip = values[7]
        pose.rightKnee = values[8]
        pose.rightAnkle = values[9]
        pose.lean = values[10]
        pose.sway = values[11]
        pose.twist = values[12]
        pose.spin = values[13]
        pose.bob = values[14]
        pose.travel = values[15]
        pose.headYaw = values[16]
        pose.headRoll = values[17]
        pose.headPitch = values[18]
        pose.point = values[19]
        pose.leftGrip = grips.left
        pose.rightGrip = grips.right
        return pose
    }
}
