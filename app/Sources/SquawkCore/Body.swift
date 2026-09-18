import Foundation
import CoreGraphics

/// Where an arm is, as two angles in degrees measured from straight down.
/// Positive swings the arm outward, away from the body.
public struct ArmPose: Sendable, Equatable {
    public let shoulder: Double
    /// Bend at the elbow, which is what separates a wave from a raised arm.
    public let elbow: Double

    public init(shoulder: Double, elbow: Double = 0) {
        self.shoulder = shoulder
        self.elbow = elbow
    }

    public static let resting = ArmPose(shoulder: 14)
}

/// Both arms, plus how much the whole body leans.
public struct BodyPose: Sendable, Equatable {
    public let left: ArmPose
    public let right: ArmPose
    /// Degrees the body tips. Small; it is a lean, not a fall.
    public let lean: Double
    /// How far the arms swing on the idle cycle, as a share of a full swing.
    public let liveliness: Double

    public init(left: ArmPose, right: ArmPose, lean: Double = 0, liveliness: Double = 1) {
        self.left = left
        self.right = right
        self.lean = lean
        self.liveliness = liveliness
    }

    /// The pose for a mood. Arms carry what a face at this size cannot: reach,
    /// recoil and slump read across a room where an eyebrow does not.
    public static func pose(for face: FaceExpression) -> BodyPose {
        switch face {
        case .calm:
            BodyPose(left: .resting, right: .resting)
        case .bored:
            // One arm propped, the other hanging, leaning off to one side.
            BodyPose(left: ArmPose(shoulder: 8), right: ArmPose(shoulder: 62, elbow: 74),
                     lean: -5, liveliness: 0.35)
        case .sleepy:
            BodyPose(left: ArmPose(shoulder: 6), right: ArmPose(shoulder: 6),
                     lean: 3, liveliness: 0.12)
        case .alert:
            BodyPose(left: ArmPose(shoulder: 26), right: ArmPose(shoulder: 26), liveliness: 1.4)
        case .urgent:
            // Both arms up, which is the one pose that reads as waving you over.
            BodyPose(left: ArmPose(shoulder: 108, elbow: 22),
                     right: ArmPose(shoulder: 108, elbow: 22), liveliness: 2.4)
        case .curious:
            BodyPose(left: ArmPose(shoulder: 10), right: ArmPose(shoulder: 58, elbow: 52),
                     lean: -7)
        case .wary:
            // Drawn back, hands up between you and it.
            BodyPose(left: ArmPose(shoulder: 44, elbow: 78),
                     right: ArmPose(shoulder: 44, elbow: 78), lean: 6, liveliness: 0.5)
        case .happy, .relieved:
            BodyPose(left: ArmPose(shoulder: 96, elbow: 16),
                     right: ArmPose(shoulder: 96, elbow: 16), liveliness: 1.8)
        case .wink:
            BodyPose(left: .resting, right: ArmPose(shoulder: 104, elbow: 30), lean: -4,
                     liveliness: 1.5)
        case .startled:
            BodyPose(left: ArmPose(shoulder: 120, elbow: 8),
                     right: ArmPose(shoulder: 120, elbow: 8), lean: -3, liveliness: 2.8)
        case .cross:
            // Arms folded in, planted.
            BodyPose(left: ArmPose(shoulder: 30, elbow: 96),
                     right: ArmPose(shoulder: 30, elbow: 96), liveliness: 0.6)
        case .sad:
            BodyPose(left: ArmPose(shoulder: 4), right: ArmPose(shoulder: 4),
                     lean: 8, liveliness: 0.3)
        case .restless:
            // Stretching: one arm up and over, the other out. A break, shown.
            BodyPose(left: ArmPose(shoulder: 118, elbow: 44),
                     right: ArmPose(shoulder: 40, elbow: 20), lean: -6, liveliness: 2.0)
        case .dizzy:
            BodyPose(left: ArmPose(shoulder: 76, elbow: -40),
                     right: ArmPose(shoulder: 76, elbow: 40), lean: -9, liveliness: 3.2)
        }
    }
}

/// Proportions of the whole companion, derived from the head so the body scales
/// with the dial rather than needing its own size.
public enum BodyGeometry {
    /// Body width and height as shares of head diameter.
    /// An egg: narrow at the shoulders, widest low down. Nearly as wide as the
    /// head, which is what stops it reading as a circle balanced on a pebble.
    public static func bodySize(head: CGFloat) -> CGSize {
        CGSize(width: head * 0.92, height: head * 0.86)
    }

    /// How much narrower the top of the egg is than its widest point.
    public static let shoulderTaper: CGFloat = 0.64

    /// The stand it sits on.
    public static func baseSize(head: CGFloat) -> CGSize {
        CGSize(width: head * 0.86, height: head * 0.12)
    }

    /// How far the body's top sits below the head's centre.
    /// Overlapping the head, so it reads as one creature rather than a circle
    /// resting on an egg.
    public static func bodyTop(head: CGFloat) -> CGFloat { head * 0.28 }

    public static func armLength(head: CGFloat) -> CGFloat { head * 0.40 }
    public static func armWidth(head: CGFloat) -> CGFloat { head * 0.145 }

    /// Room above the head for the speech bubble.
    public static func bubbleHeight(head: CGFloat) -> CGFloat { max(96, head * 0.56) }

    /// The window a companion needs, given the head it is built around. Wider
    /// than the head because arms swing out, taller because of the body, and
    /// taller again because it speaks above itself.
    public static func canvas(head: CGFloat) -> CGSize {
        // Tall enough for the body and its stand, not just to the body's edge.
        CGSize(width: max(head * 1.52, 300),
               height: head * 1.74 + bubbleHeight(head: head))
    }
}
