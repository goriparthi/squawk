import Foundation

/// One frame of the dance. Angles are degrees, hue is 0 to 1.
public struct DanceFrame: Sendable, Equatable {
    public let leftArm: Double
    public let rightArm: Double
    public let leftElbow: Double
    public let rightElbow: Double
    public let leftLeg: Double
    public let rightLeg: Double
    public let bob: Double
    public let spin: Double
    public let lean: Double
    public let headBop: Double
    /// Where on the rainbow everything is right now.
    public let hue: Double
}

/// The dance. Four bars that do not all repeat at the same rate, so it reads as
/// a routine rather than a loop: the arms are on the beat, the spin is on every
/// other bar, and the hue runs slower than both.
public enum Dance {
    /// Beats per second. Roughly 132bpm, which is the tempo of not being able
    /// to help yourself.
    public static let tempo: Double = 2.2
    public static let duration: TimeInterval = 12

    public static func frame(at elapsed: TimeInterval) -> DanceFrame {
        let beat = elapsed * tempo
        let turns = beat * 2 * .pi
        let half = turns / 2
        let quarter = turns / 4

        // Arms alternate on the beat and throw up on the bar.
        let pump = sin(turns)
        // Capped short of straight up: past that the arm carries on round and
        // comes back down the other side, which reads as a broken joint.
        let raise = (0.5 + 0.5 * sin(quarter)) * 34

        return DanceFrame(
            leftArm: min(168, 92 + raise + pump * 38),
            rightArm: min(168, 92 + raise - pump * 38),
            leftElbow: -28 + pump * 34,
            rightElbow: -28 - pump * 34,
            // Legs kick opposite the arm on the same side, which is what makes
            // it a dance and not a jumping jack.
            leftLeg: -pump * 20,
            rightLeg: pump * 20,
            bob: abs(sin(turns)) * 0.09,
            spin: sin(half) * 26,
            lean: sin(half + .pi / 3) * 9,
            headBop: sin(turns) * 7,
            hue: (elapsed * 0.28).truncatingRemainder(dividingBy: 1)
        )
    }

    /// Rainbow, but not a fairground: the colours stay saturated and bright
    /// enough to read against a dark pet on a light desktop.
    public static func colour(at hue: Double) -> (hue: Double, saturation: Double, brightness: Double) {
        (hue: hue.truncatingRemainder(dividingBy: 1), saturation: 0.72, brightness: 0.96)
    }
}
