import Foundation
import CoreGraphics

/// Where an arm is, as two angles in degrees measured from straight down.
/// Positive swings the arm outward, away from the body.
/// What a hand is doing. Fingers are what make a gesture legible at all: a
/// blob on the end of an arm can only wave.
public enum Grip: Sendable, Equatable, CaseIterable {
    case open
    case fist
    /// One finger out, the rest closed.
    case point
    /// Relaxed, which is neither flat nor clenched and is what a hand does when
    /// nobody is asking anything of it.
    case loose

    /// How far each finger is curled, 0 straight and 1 closed, thumb last.
    public var curls: [Double] {
        switch self {
        case .open: [0, 0, 0, 0]
        case .fist: [1, 1, 1, 0.85]
        case .point: [0, 1, 1, 0.9]
        case .loose: [0.32, 0.38, 0.44, 0.3]
        }
    }
}

public struct ArmPose: Sendable, Equatable {
    public let shoulder: Double
    /// Bend at the elbow, which is what separates a wave from a raised arm.
    public let elbow: Double
    public let grip: Grip

    public init(shoulder: Double, elbow: Double = 0, grip: Grip = .loose) {
        self.shoulder = shoulder
        self.elbow = elbow
        self.grip = grip
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
            // Both arms up, which is the one pose that reads as waving you over,
            // and both hands open, which is what makes it a wave.
            BodyPose(left: ArmPose(shoulder: 92, elbow: 30, grip: .open),
                     right: ArmPose(shoulder: 92, elbow: 30, grip: .open), liveliness: 2.4)
        case .curious:
            BodyPose(left: ArmPose(shoulder: 10), right: ArmPose(shoulder: 58, elbow: 52,
                                                                grip: .point), lean: -7)
        case .wary:
            // Drawn back, hands up between you and it.
            BodyPose(left: ArmPose(shoulder: 44, elbow: 78, grip: .open),
                     right: ArmPose(shoulder: 44, elbow: 78, grip: .open), lean: 6, liveliness: 0.5)
        case .happy, .relieved:
            BodyPose(left: ArmPose(shoulder: 88, elbow: 24, grip: .open),
                     right: ArmPose(shoulder: 88, elbow: 24, grip: .open), liveliness: 1.8)
        case .wink:
            BodyPose(left: .resting, right: ArmPose(shoulder: 94, elbow: 34), lean: -4,
                     liveliness: 1.5)
        case .startled:
            BodyPose(left: ArmPose(shoulder: 98, elbow: 10),
                     right: ArmPose(shoulder: 98, elbow: 10), lean: -3, liveliness: 2.8)
        case .cross:
            // Folded across, not reaching out: the elbow turns the forearm back
            // toward the body, which is what folded arms actually look like.
            BodyPose(left: ArmPose(shoulder: 52, elbow: -104, grip: .fist),
                     right: ArmPose(shoulder: 52, elbow: -104, grip: .fist), liveliness: 0.6)
        case .sad:
            BodyPose(left: ArmPose(shoulder: 4), right: ArmPose(shoulder: 4),
                     lean: 8, liveliness: 0.3)
        case .restless:
            // Stretching: one arm up and over, the other out. A break, shown.
            BodyPose(left: ArmPose(shoulder: 96, elbow: 48),
                     right: ArmPose(shoulder: 38, elbow: 18), lean: -6, liveliness: 2.0)
        case .dizzy:
            // The last rung of angry. Arms straight up and shaking, leaning in
            // at you, rather than the sideways flap that read as flustered.
            BodyPose(left: ArmPose(shoulder: 152, elbow: -22, grip: .fist),
                     right: ArmPose(shoulder: 152, elbow: -22, grip: .fist), lean: 5, liveliness: 2.6)
        }
    }
}

/// Proportions of the whole companion, derived from the head so the body scales
/// with the dial rather than needing its own size.
public enum BodyGeometry {
    /// Body width and height as shares of head diameter.
    /// An egg: narrow at the shoulders, widest low down. Nearly as wide as the
    /// head, which is what stops it reading as a circle balanced on a pebble.
    

    /// Where the egg's widest point sits, as a fraction of its height from the
    /// bottom. Shared by the drawing and by anything attaching to the surface.
    public static let widestAt: CGFloat = 0.40

    /// The egg's half width at a height, as a fraction of its widest. Modelled
    /// as an ellipse above the widest point, which matches the drawn curve
    /// closely enough for attaching a limb to the surface.
    public static func halfWidthFraction(atFractionBelowTop drop: CGFloat) -> CGFloat {
        let toWidest = 1 - widestAt
        guard drop < toWidest else { return 1 }
        let u = 1 - drop / toWidest
        return (1 - u * u).squareRoot()
    }

    /// The stand it sits on.
    

    /// How far the body's top sits below the head's centre.
    /// Overlapping the head, so it reads as one creature rather than a circle
    /// resting on an egg.
    

    /// Short and broad. Long thin limbs read as antennae.
    

    

    /// The shell around the scope: a squircle with small ear bumps, which is
    /// what gives the silhouette its head rather than a floating circle.
    

    

    

    /// Room above the head for the speech bubble.
    /// The card inside is the same size whatever the pet is, so the bubble has
    /// a floor the head cannot shrink it past.
    public static func bubbleHeight(head: CGFloat) -> CGFloat {
        max(DialGeometry.bubbleFloor, head * 0.56)
    }

    /// The window a companion needs, given the head it is built around. Wider
    /// than the head because arms swing out, taller because of the body, and
    /// taller again because it speaks above itself.
    public static func canvas(head: CGFloat) -> CGSize {
        // Tall enough for the body and its stand, not just to the body's edge,
        // and wide enough for the shell's ears as well as the arms.
        CGSize(width: max(head * 1.80, DialGeometry.bubbleWidth() + 16),
               height: head * 1.96 + bubbleHeight(head: head))
    }
}
