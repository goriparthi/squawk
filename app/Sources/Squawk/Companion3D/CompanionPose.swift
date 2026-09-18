import AppKit
import SceneKit
import SquawkCore

/// Puts a pose onto the model. Kept apart from building it so the geometry is
/// described once and driven from several places: moods, the walk and the dance.
@MainActor
extension CompanionScene {
    /// Degrees, because every pose type in the app is in degrees. SceneKit is
    /// not, and mixing the two is how a shoulder ends up 57 times too far over.
    static func radians(_ degrees: Double) -> CGFloat { CGFloat(degrees * .pi / 180) }

    /// A mood: arms and lean, the same vocabulary the flat drawing uses, so one
    /// set of poses drives both renderers.
    func apply(_ pose: BodyPose) {
        setArm(shoulders.left, elbows.left, shoulder: pose.left.shoulder,
               elbow: pose.left.elbow, side: -1)
        setArm(shoulders.right, elbows.right, shoulder: pose.right.shoulder,
               elbow: pose.right.elbow, side: 1)
        setGrip(knuckles.left, pose.left.grip, side: -1)
        setGrip(knuckles.right, pose.right.grip, side: 1)
        bodyPivot.eulerAngles.x = Self.radians(pose.lean)
    }

    /// One moment of a walk: legs, arms and everything the hips do.
    func apply(_ stride: Stride) {
        setLeg(hips.left, knees.left, stride.left)
        setLeg(hips.right, knees.right, stride.right)
        setAnkle(ankles.left, stride.left)
        setAnkle(ankles.right, stride.right)
        setGrip(knuckles.left, .loose, side: -1)
        setGrip(knuckles.right, .loose, side: 1)
        setArm(shoulders.left, elbows.left, shoulder: 12 + stride.leftArm, elbow: -18, side: -1)
        setArm(shoulders.right, elbows.right, shoulder: 12 + stride.rightArm, elbow: -18, side: 1)
        bodyPivot.position.y = CGFloat(stride.bob)
        bodyPivot.eulerAngles.z = Self.radians(stride.sway)
        bodyPivot.eulerAngles.y = Self.radians(stride.twist)
        headPivot.eulerAngles.y = Self.radians(-stride.twist * 0.6)
    }

    /// One frame of the dance, which owns the whole body including the hue.
    func apply(_ frame: DanceFrame) {
        setArm(shoulders.left, elbows.left, shoulder: frame.leftArm,
               elbow: frame.leftElbow, side: -1)
        setArm(shoulders.right, elbows.right, shoulder: frame.rightArm,
               elbow: frame.rightElbow, side: 1)
        setLeg(hips.left, knees.left,
               LegPose(hip: frame.leftLeg, knee: max(0, frame.leftLeg), load: 0.5))
        setLeg(hips.right, knees.right,
               LegPose(hip: frame.rightLeg, knee: max(0, frame.rightLeg), load: 0.5))
        setAnkle(ankles.left, LegPose(hip: 0, knee: 0, ankle: -frame.leftLeg, load: 0.5))
        setAnkle(ankles.right, LegPose(hip: 0, knee: 0, ankle: -frame.rightLeg, load: 0.5))
        // Hands open on the beat and close off it, which is what reads as
        // dancing rather than flailing.
        let clap = sin(frame.spin) > 0
        setGrip(knuckles.left, clap ? .open : .fist, side: -1)
        setGrip(knuckles.right, clap ? .open : .fist, side: 1)
        bodyPivot.position.y = CGFloat(frame.bob)
        bodyPivot.eulerAngles = SCNVector3(
            Self.radians(frame.lean), Self.radians(frame.spin), Self.radians(frame.lean * 0.4))
        headPivot.eulerAngles.z = Self.radians(frame.headBop)

        let colour = Dance.colour(at: frame.hue)
        tint(NSColor(calibratedHue: CGFloat(colour.hue), saturation: CGFloat(colour.saturation),
                     brightness: CGFloat(colour.brightness), alpha: 1))
    }

    /// Back to standing, in its own colours.
    func rest() {
        apply(BodyPose.pose(for: .calm))
        setLeg(hips.left, knees.left, LegPose(hip: 0, knee: 0, load: 0.5))
        setLeg(hips.right, knees.right, LegPose(hip: 0, knee: 0, load: 0.5))
        setAnkle(ankles.left, LegPose(hip: 0, knee: 0, load: 0.5))
        setAnkle(ankles.right, LegPose(hip: 0, knee: 0, load: 0.5))
        bodyPivot.position.y = 0
        bodyPivot.eulerAngles = SCNVector3Zero
        headPivot.eulerAngles = SCNVector3Zero
        tint(nil)
    }

    // MARK: - Joints

    /// Shoulder angles are measured from straight down and swing outward, which
    /// is a roll about z. The elbow bends in the same plane.
    private func setArm(
        _ shoulder: SCNNode, _ elbow: SCNNode,
        shoulder degrees: Double, elbow bend: Double, side: Double
    ) {
        // A roll of +angle carries the arm away from the body on the right and
        // -angle does the same on the left. Signed the other way both arms
        // swing inward and vanish behind the belly, which is where they were.
        shoulder.eulerAngles.z = Self.radians(degrees * side)
        elbow.eulerAngles.z = Self.radians(bend * side)
        // A raised arm also swings a little forward, or a pose seen head on
        // looks like a cardboard cut out.
        shoulder.eulerAngles.x = Self.radians(min(degrees, 90) * 0.12)
    }

    /// Hips swing fore and aft, so they are a pitch about x, not a roll.
    /// Curls each finger toward the palm. A thumb folds across rather than in,
    /// which is why it keeps its own resting angle underneath.
    private func setGrip(_ digits: [SCNNode], _ grip: Grip, side: Double) {
        let curls = grip.curls
        for (index, knuckle) in digits.enumerated() where index < curls.count {
            let thumb = index == digits.count - 1
            knuckle.eulerAngles.x = Self.radians(curls[index] * (thumb ? 55 : 92))
            if thumb { knuckle.eulerAngles.z = Self.radians(side * -70) }
        }
    }

    private func setLeg(_ hip: SCNNode, _ knee: SCNNode, _ pose: LegPose) {
        // Positive hip is forward, which is a negative pitch, and a knee only
        // bends the other way: the shin goes back, never through the shin bone.
        hip.eulerAngles.x = Self.radians(-pose.hip)
        knee.eulerAngles.x = Self.radians(pose.knee)
    }

    /// The ankle keeps the sole level with the ground while the leg swings.
    private func setAnkle(_ ankle: SCNNode, _ pose: LegPose) {
        ankle.eulerAngles.x = Self.radians(-pose.ankle)
    }
}
