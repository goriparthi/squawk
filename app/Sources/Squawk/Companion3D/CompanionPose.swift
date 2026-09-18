import AppKit
import SceneKit
import SquawkCore

/// Writes a pose onto the model. Kept apart from building it so the geometry is
/// described once, and separate from deciding the pose so everything the pet
/// does goes through the same springs on its way to the joints.
@MainActor
extension CompanionScene {
    /// Degrees, because every pose type in the app is in degrees. SceneKit is
    /// not, and mixing the two is how a shoulder ends up 57 times too far over.
    static func radians(_ degrees: Double) -> CGFloat { CGFloat(degrees * .pi / 180) }

    func apply(_ pose: Pose3D) {
        setArm(shoulders.left, elbows.left,
               shoulder: pose.leftShoulder, elbow: pose.leftElbow, side: -1)
        setArm(shoulders.right, elbows.right,
               shoulder: pose.rightShoulder, elbow: pose.rightElbow, side: 1,
               forward: pose.point)
        setGrip(knuckles.left, pose.leftGrip, side: -1)
        setGrip(knuckles.right, pose.rightGrip, side: 1)

        setLeg(hips.left, knees.left, ankles.left,
               hip: pose.leftHip, knee: pose.leftKnee, ankle: pose.leftAnkle)
        setLeg(hips.right, knees.right, ankles.right,
               hip: pose.rightHip, knee: pose.rightKnee, ankle: pose.rightAnkle)

        bodyPivot.position.y = CGFloat(pose.bob)
        bodyPivot.eulerAngles = SCNVector3(Self.radians(pose.lean),
                                           Self.radians(pose.twist + pose.spin),
                                           Self.radians(pose.sway))
        headPivot.eulerAngles = SCNVector3(Self.radians(pose.headPitch),
                                           Self.radians(pose.headYaw),
                                           Self.radians(pose.headRoll))
        root.position.x = CGFloat(pose.travel)
    }

    // MARK: - Joints

    /// Shoulder angles are measured from straight down and swing outward, which
    /// is a roll about z. The elbow bends in the same plane.
    private func setArm(
        _ shoulder: SCNNode, _ elbow: SCNNode,
        shoulder degrees: Double, elbow bend: Double, side: Double,
        forward: Double = 0
    ) {
        // A roll of +angle carries the arm away from the body on the right and
        // -angle does the same on the left. Signed the other way both arms
        // swing inward and vanish behind the belly.
        shoulder.eulerAngles.z = Self.radians(degrees * side)
        elbow.eulerAngles.z = Self.radians(bend * side)
        // A raised arm also swings a little forward, or a pose seen head on
        // looks like a cardboard cut out.
        // A raised arm also swings a little forward, or a pose seen head on
        // looks like a cardboard cut out. Pointing is that, taken all the way.
        shoulder.eulerAngles.x = Self.radians(min(degrees, 90) * 0.12 - forward)
    }

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

    /// Hips swing fore and aft, so they are a pitch about x, not a roll.
    /// Positive hip is forward, which is a negative pitch, and a knee only bends
    /// the one way: the shin goes back, never through the shin bone.
    private func setLeg(
        _ hip: SCNNode, _ knee: SCNNode, _ ankle: SCNNode,
        hip degrees: Double, knee bend: Double, ankle foot: Double
    ) {
        hip.eulerAngles.x = Self.radians(-degrees)
        knee.eulerAngles.x = Self.radians(max(0, bend))
        // The ankle keeps the sole level with the ground while the leg swings.
        ankle.eulerAngles.x = Self.radians(-foot)
    }
}
