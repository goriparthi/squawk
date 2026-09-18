import Foundation
import CoreGraphics

/// The face as continuous values rather than a discrete expression. Everything
/// drawn is interpolated, because a face that snaps between states reads as a
/// status light, not a companion.
public struct FaceFrame: Sendable, Equatable {
    /// Eye height as a share of the fully open eye.
    public var openness: Double = 1
    /// Degrees each eye is rotated; inner edge down is negative.
    public var tilt: Double = 0
    /// 0 is an open eye, 1 is a closed arc.
    public var squint: Double = 0
    /// Closes the left eye alone, for a wink.
    public var winkLeft: Double = 0
    /// Positive curves up, negative down.
    public var mouth: Double = 0
    /// Crossfades the mouth from a stroke to the little triangle.
    public var triangle: Double = 0
    /// Brows fade in rather than appearing.
    public var brows: Double = 0
    /// One eye riding higher than the other.
    public var headTilt: Double = 0
    /// Crossfades the eye into two crossed strokes.
    public var crossedOut: Double = 0
    /// Looks away rather than at you, in units of eye width.
    public var gazeBias: Double = 0
    /// The eye colour, interpolated like everything else so a mood shifts hue
    /// rather than switching it.
    public var red: Double = FaceTint.brand.red
    public var green: Double = FaceTint.brand.green
    public var blue: Double = FaceTint.brand.blue

    public init() {}

    public static func target(for face: FaceExpression) -> FaceFrame {
        var frame = FaceFrame()
        frame.openness = face.openness
        frame.tilt = face.eyeTilt
        frame.squint = face.isArc ? 1 : 0
        frame.winkLeft = face.winksLeftEye ? 1 : 0
        frame.mouth = face.mouthCurve
        frame.triangle = face.mouthIsTriangle ? 1 : 0
        frame.brows = face.hasBrows ? 1 : 0
        frame.headTilt = face.tilt
        frame.crossedOut = face.isCrossedOut ? 1 : 0
        frame.gazeBias = face.gazeBias
        frame.red = face.tint.red
        frame.green = face.tint.green
        frame.blue = face.tint.blue
        return frame
    }

    /// Exponential approach, which is frame-rate independent: the same motion
    /// whether the display runs at 60 or 120.
    public static func approach(
        _ current: FaceFrame,
        toward goal: FaceFrame,
        dt: Double,
        halfLife: Double = 0.075
    ) -> FaceFrame {
        guard dt > 0 else { return current }
        let t = 1 - pow(2, -dt / max(halfLife, 0.001))
        var next = current
        next.openness = lerp(current.openness, goal.openness, t)
        next.tilt = lerp(current.tilt, goal.tilt, t)
        next.squint = lerp(current.squint, goal.squint, t)
        next.winkLeft = lerp(current.winkLeft, goal.winkLeft, t)
        next.mouth = lerp(current.mouth, goal.mouth, t)
        next.triangle = lerp(current.triangle, goal.triangle, t)
        next.brows = lerp(current.brows, goal.brows, t)
        next.headTilt = lerp(current.headTilt, goal.headTilt, t)
        next.crossedOut = lerp(current.crossedOut, goal.crossedOut, t)
        next.gazeBias = lerp(current.gazeBias, goal.gazeBias, t)
        // Colour eases more slowly than shape, so a mood washes in rather than
        // flicking over as the eyes move.
        let colourT = 1 - pow(2, -dt / 0.22)
        next.red = lerp(current.red, goal.red, colourT)
        next.green = lerp(current.green, goal.green, colourT)
        next.blue = lerp(current.blue, goal.blue, colourT)
        return next
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * min(max(t, 0), 1)
    }

    public func isNear(_ other: FaceFrame, tolerance: Double = 0.004) -> Bool {
        abs(openness - other.openness) < tolerance
            && abs(tilt - other.tilt) < tolerance * 40
            && abs(squint - other.squint) < tolerance
            && abs(winkLeft - other.winkLeft) < tolerance
            && abs(mouth - other.mouth) < tolerance
            && abs(triangle - other.triangle) < tolerance
            && abs(brows - other.brows) < tolerance
            && abs(headTilt - other.headTilt) < tolerance
            && abs(crossedOut - other.crossedOut) < tolerance
            && abs(gazeBias - other.gazeBias) < tolerance
            && abs(red - other.red) < tolerance
            && abs(green - other.green) < tolerance
            && abs(blue - other.blue) < tolerance
    }
}

/// A blink is a scripted squash, not a fade: it shuts fast and opens a little
/// slower, the way an eyelid does.
public enum Blink {
    public static let duration: Double = 0.22
    private static let shutAt: Double = 0.4

    /// The multiplier on eye height at a point through the blink.
    public static func openness(at elapsed: Double) -> Double {
        guard elapsed >= 0, elapsed <= duration else { return 1 }
        let phase = elapsed / duration
        if phase < shutAt {
            return 1 - easeIn(phase / shutAt) * 0.94
        }
        return 0.06 + easeOut((phase - shutAt) / (1 - shutAt)) * 0.94
    }

    static func easeIn(_ t: Double) -> Double { t * t }
    static func easeOut(_ t: Double) -> Double { 1 - (1 - t) * (1 - t) }
}
