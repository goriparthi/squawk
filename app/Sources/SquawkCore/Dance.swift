import Foundation

/// One frame of the dance. Angles are degrees, hue is 0 to 1.
public struct DanceFrame: Sendable, Equatable {
    public let hue: Double
    public let move: Dance.Move
}

/// A routine rather than a loop of one move. Five moves, two seconds each,
/// borrowed from the Bollywood floor and from the internet: the lightbulb, a
/// shoulder shimmy, the Naatu knee kicks, the horse reins everyone already
/// knows, and a spin to finish. It repeats until it is told to stop.
public enum Dance {
    /// Beats per second. Roughly 132bpm, which is the tempo of not being able
    /// to help yourself.
    public static let tempo: Double = 2.2
    /// One time through the routine. It loops from the top until the belly is
    /// double tapped again, so a dance is something you end rather than wait out.
    public static let duration: TimeInterval = 10
    public static let moveLength: TimeInterval = 2

    public enum Move: String, Sendable, CaseIterable {
        /// Screw the bulb in with one hand, pat the dog with the other. The one
        /// move everybody can do and nobody can name.
        case lightbulb
        case shimmy
        /// Alternating high knees with the opposite arm thrown out.
        case naatu
        /// Both hands on the reins, hopping. You know the one.
        case horse
        case spin
    }

    public static func frame(at elapsed: TimeInterval) -> DanceFrame {
        DanceFrame(
            hue: (elapsed * (1 / duration)).truncatingRemainder(dividingBy: 1),
            move: move(at: elapsed)
        )
    }

    public static func move(at elapsed: TimeInterval) -> Move {
        let looped = elapsed.truncatingRemainder(dividingBy: duration)
        let index = Int(looped / moveLength) % Move.allCases.count
        return Move.allCases[index]
    }

    /// The whole body at this moment of the routine.
    /// `tempo` in beats per second. Passed the tempo of whatever is playing,
    /// the routine locks to the music instead of to its own metronome.
    public static func pose(at elapsed: TimeInterval, tempo: Double = Dance.tempo) -> Pose3D {
        let looped = elapsed.truncatingRemainder(dividingBy: duration)
        let move = move(at: elapsed)
        let within = looped.truncatingRemainder(dividingBy: moveLength)
        let beat = elapsed * tempo * 2 * .pi
        var pose = Pose3D()
        // Every move sits on the same bounce, which is what holds a routine
        // together when the arms are doing something different every two bars.
        pose.bob = abs(sin(beat / 2)) * 0.05
        pose.headRoll = sin(beat) * 6

        switch move {
        case .lightbulb:
            let swap = sin(within * .pi / moveLength * 2) >= 0
            let high: Double = 148 + sin(beat) * 10
            let low: Double = 42
            pose.leftShoulder = swap ? high : low
            pose.rightShoulder = swap ? low : high
            pose.leftElbow = swap ? -34 : -62
            pose.rightElbow = swap ? -62 : -34
            pose.leftGrip = swap ? .point : .loose
            pose.rightGrip = swap ? .loose : .point
            pose.sway = sin(beat) * 7
            pose.twist = sin(beat) * 9
            pose.headYaw = swap ? 12 : -12

        case .shimmy:
            let shake = sin(beat * 2)
            pose.leftShoulder = 58 + shake * 16
            pose.rightShoulder = 58 - shake * 16
            pose.leftElbow = -58
            pose.rightElbow = -58
            pose.leftGrip = .open
            pose.rightGrip = .open
            pose.twist = shake * 14
            pose.sway = -shake * 6
            pose.headYaw = shake * 10
            pose.lean = 4

        case .naatu:
            let kick = sin(beat)
            let lead = kick >= 0
            pose.leftHip = lead ? 52 : -6
            pose.leftKnee = lead ? 68 : 6
            pose.rightHip = lead ? -6 : 52
            pose.rightKnee = lead ? 6 : 68
            pose.leftShoulder = lead ? 34 : 124
            pose.rightShoulder = lead ? 124 : 34
            pose.leftElbow = lead ? -20 : -8
            pose.rightElbow = lead ? -8 : -20
            pose.leftGrip = .point
            pose.rightGrip = .point
            pose.lean = 7
            pose.twist = kick * 12
            pose.bob += abs(kick) * 0.02

        case .horse:
            let hop = abs(sin(beat))
            pose.leftShoulder = 96
            pose.rightShoulder = 96
            pose.leftElbow = -74 + hop * 22
            pose.rightElbow = -74 + hop * 22
            pose.leftGrip = .fist
            pose.rightGrip = .fist
            pose.leftHip = sin(beat) * 16
            pose.rightHip = -sin(beat) * 16
            pose.leftKnee = max(0, sin(beat)) * 26
            pose.rightKnee = max(0, -sin(beat)) * 26
            pose.bob = hop * 0.08
            pose.lean = 6
            pose.sway = sin(beat) * 5

        case .spin:
            // One full turn over the first half, then a held finish.
            let turn = min(1, within / (moveLength * 0.6))
            pose.spin = turn * 360
            let finish = within > moveLength * 0.6
            pose.leftShoulder = finish ? 158 : 82
            pose.rightShoulder = finish ? 28 : 82
            pose.leftElbow = finish ? -12 : -46
            pose.rightElbow = finish ? -40 : -46
            pose.leftGrip = finish ? .point : .open
            pose.rightGrip = .fist
            pose.lean = finish ? -6 : 3
            pose.headRoll = finish ? -14 : sin(beat) * 6
            pose.bob = finish ? 0.01 : pose.bob
        }

        // The legs keep a little tension under everything, so it is never
        // standing on straight sticks.
        pose.leftKnee = max(pose.leftKnee, 5)
        pose.rightKnee = max(pose.rightKnee, 5)
        pose.leftAnkle = -pose.leftHip * 0.5
        pose.rightAnkle = -pose.rightHip * 0.5
        return pose
    }

    /// A tempo worth dancing at. Anything can be detected, but a routine at 40
    /// or 220 beats a minute reads as broken rather than as slow or fast, so
    /// what comes in gets halved or doubled until it lands somewhere sensible.
    public static func danceable(_ detected: Double?) -> Double {
        guard var tempo = detected, tempo > 0.1, tempo.isFinite else { return Dance.tempo }
        while tempo < 1.4 { tempo *= 2 }
        while tempo > 3.2 { tempo /= 2 }
        return tempo
    }

    /// Rainbow, but not a fairground: the colours stay saturated and bright
    /// enough to read against a dark pet on a light desktop.
    public static func colour(at hue: Double) -> (hue: Double, saturation: Double, brightness: Double) {
        (hue: hue.truncatingRemainder(dividingBy: 1), saturation: 0.72, brightness: 0.96)
    }
}
