import AppKit
import SquawkCore

/// The face's state over time: the interpolation toward an expression, the
/// blink, and the gaze drift. Held apart from any view because two renderers
/// need it, the flat dial and the modelled companion's screen, and a face that
/// blinked at two different moments would read as two creatures.
@MainActor
final class FaceAnimator {
    var expression: FaceExpression = .calm {
        didSet {
            guard expression != oldValue else { return }
            goal = FaceFrame.target(for: expression, resting: restingEye)
        }
    }

    /// The character's own eye colour, used for every neutral expression. The
    /// moods keep their own colours, because orange and red mean something.
    var restingEye: FaceTint? {
        didSet {
            guard restingEye != oldValue else { return }
            goal = FaceFrame.target(for: expression, resting: restingEye)
        }
    }

    private var frame = FaceFrame()
    private var goal = FaceFrame()
    private var lastTick: CFTimeInterval = 0
    private var blinkStartedAt: CFTimeInterval = -1
    private var nextBlinkAt: CFTimeInterval = 0
    private var gaze = CGPoint.zero
    private var gazeGoal = CGPoint.zero
    private var nextGazeAt: CFTimeInterval = 0
    private var clock: CFTimeInterval = 0

    /// How wide the mouth is open while it speaks. Set from whatever is making
    /// the sound; zero when it is not talking.
    var talking: Double = 0

    /// The current moment, as something that can draw itself.
    var artist: FaceArtist {
        FaceArtist(talking: talking, frame: frame, gaze: gaze, clock: clock,
                   blinkStartedAt: blinkStartedAt)
    }

    /// Called when the animation starts again after a pause, so a long gap does
    /// not arrive as one enormous step.
    func resume(at now: CFTimeInterval = CACurrentMediaTime()) {
        lastTick = now
        nextBlinkAt = now + Double.random(in: 2.4...6.0)
        nextGazeAt = now + Double.random(in: 1.6...4.0)
    }

    /// Jumps straight to the target. An offscreen render has no clock to
    /// interpolate with, and a contact sheet wants the settled face anyway.
    func settle() {
        frame = goal
    }

    func advance(to now: CFTimeInterval = CACurrentMediaTime()) {
        let dt = min(now - lastTick, 1.0 / 20)
        lastTick = now
        clock = now

        frame = FaceFrame.approach(frame, toward: goal, dt: dt)

        if now >= nextBlinkAt, blinkStartedAt < 0 {
            blinkStartedAt = now
        }
        if blinkStartedAt >= 0, now - blinkStartedAt > Blink.duration {
            blinkStartedAt = -1
            // Never a metronome; an even rhythm reads as a machine ticking.
            nextBlinkAt = now + Double.random(in: 2.4...6.4)
        }

        if now >= nextGazeAt {
            gazeGoal = CGPoint(x: .random(in: -0.16...0.16), y: .random(in: -0.08...0.08))
            nextGazeAt = now + Double.random(in: 1.6...4.2)
        }
        let approach = 1 - pow(2, -dt / 0.22)
        gaze.x += (gazeGoal.x - gaze.x) * approach
        gaze.y += (gazeGoal.y - gaze.y) * approach
    }
}
