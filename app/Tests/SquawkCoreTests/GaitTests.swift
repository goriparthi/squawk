import XCTest
@testable import SquawkCore

final class GaitTests: XCTestCase {
    /// A walk where both legs do the same thing at the same time is a hop.
    func testTheLegsAreHalfAStrideApart() {
        for step in stride(from: 0.0, to: 1.0, by: 0.05) {
            let now = Gait.stride(phase: step)
            let later = Gait.stride(phase: (step + 0.5).truncatingRemainder(dividingBy: 1))
            XCTAssertEqual(now.left.hip, later.right.hip, accuracy: 0.001,
                           "the right leg should be doing what the left did half a stride ago")
        }
    }

    /// Arms swing against their own leg. Swinging with it is a march. Taken
    /// over the whole stride rather than sample by sample, because the arm
    /// trails its leg and the two do briefly share a sign at the crossing.
    func testTheArmsOpposeTheLegs() {
        let agreement = stride(from: 0.0, to: 1.0, by: 0.01)
            .map { Gait.stride(phase: $0) }
            .reduce(0.0) { $0 + $1.left.hip * $1.leftArm }
        XCTAssertLessThan(agreement, 0, "the left arm swung with the left leg")
    }

    /// An arm is dragged, not driven: it reaches the end of its swing after the
    /// leg it answers. Without the lag both ends of the body turn at once and
    /// the walk reads as clockwork.
    func testTheArmTrailsItsLeg() {
        let samples = stride(from: 0.0, to: 1.0, by: 0.002).map { Gait.stride(phase: $0) }
        let legPeak = samples.enumerated().max { $0.element.right.hip < $1.element.right.hip }?.offset ?? 0
        let armPeak = samples.enumerated().max { $0.element.rightArm < $1.element.rightArm }?.offset ?? 0
        // The arm opposes its leg, so its peak sits half a stride away; the lag
        // is how far past that half stride it actually lands.
        let gap = (Double(armPeak - legPeak) * 0.002 + 1).truncatingRemainder(dividingBy: 1)
        XCTAssertEqual(gap - 0.5, Gait.armLag, accuracy: 0.01)
        XCTAssertGreaterThan(Gait.armLag, 0, "the arm should not lead")
    }

    /// A knee that bends the other way is a broken leg, whatever the phase.
    func testKneesNeverBendBackward() {
        for step in stride(from: 0.0, through: 1.0, by: 0.01) {
            let moment = Gait.stride(phase: step)
            XCTAssertGreaterThanOrEqual(moment.left.knee, 0, "at \(step)")
            XCTAssertGreaterThanOrEqual(moment.right.knee, 0, "at \(step)")
        }
    }

    /// The hips rise over each planted foot, so twice a stride, not once.
    func testTheBobIsTwicePerStride() {
        let samples = stride(from: 0.0, to: 1.0, by: 0.005).map { Gait.stride(phase: $0).bob }
        var peaks = 0
        for index in 1..<(samples.count - 1)
        where samples[index] > samples[index - 1] && samples[index] >= samples[index + 1] {
            peaks += 1
        }
        XCTAssertEqual(peaks, 2, "the hips should rise once over each foot")
    }

    /// Standing still is the same maths with nothing turned up, which is what
    /// lets a walk slow to a stop rather than switching off.
    func testNoEffortIsStandingStill() {
        let still = Gait.stride(phase: 0.37, effort: 0)
        XCTAssertEqual(still.left.hip, 0, accuracy: 0.0001)
        XCTAssertEqual(still.right.knee, 0, accuracy: 0.0001)
        XCTAssertEqual(still.bob, 0, accuracy: 0.0001)
        XCTAssertEqual(still.leftArm, 0, accuracy: 0.0001)
    }

    func testThePhaseWraps() {
        XCTAssertEqual(Gait.phase(at: 0), 0, accuracy: 0.0001)
        // Either side of the wrap is the same place on the cycle, and which one
        // a stride lands on is down to the last bit of the division.
        let full = Gait.phase(at: 1 / Gait.cadence)
        XCTAssertLessThan(min(full, 1 - full), 0.0001, "one stride should land back at the start")
        XCTAssertLessThan(Gait.phase(at: 99), 1)
    }

    /// Unhurried. A pet that scurries on reads as panicking rather than
    /// arriving, and this is the number that decides it.
    func testItWalksAtAHumanPace() {
        XCTAssertLessThan(Gait.cadence, 1.1, "faster than a person walks")
        XCTAssertGreaterThan(Gait.cadence, 0.6, "slower than a person walks")
    }

    /// A knee that locks straight through stance is a stilt. A walk takes the
    /// weight by giving a little.
    func testTheKneeGivesWhenTheWeightLands() {
        let planted = stride(from: 0.0, through: 1.0, by: 0.01)
            .map { Gait.stride(phase: $0).left }
            .filter { $0.load > 0.5 }
        XCTAssertGreaterThan(planted.map(\.knee).max() ?? 0, 1,
                             "the planted knee never flexed at all")
    }
}

final class DanceTests: XCTestCase {
    /// An arm past straight up carries on round and comes back down the other
    /// side, which reads as a joint giving way.
    func testArmsStayWithinTheirJoint() {
        for step in stride(from: 0.0, through: Dance.duration * 2, by: 0.02) {
            let pose = Dance.pose(at: step)
            XCTAssertLessThanOrEqual(pose.leftShoulder, 170, "at \(step)")
            XCTAssertLessThanOrEqual(pose.rightShoulder, 170, "at \(step)")
            XCTAssertGreaterThanOrEqual(pose.leftKnee, 0, "a knee bent backward at \(step)")
            XCTAssertGreaterThanOrEqual(pose.rightKnee, 0, "a knee bent backward at \(step)")
        }
    }

    /// Both arms doing the same thing throughout is a stretch, not a dance.
    func testTheArmsTakeTurns() {
        let apart = stride(from: 0.0, through: Dance.duration, by: 0.05)
            .map { abs(Dance.pose(at: $0).leftShoulder - Dance.pose(at: $0).rightShoulder) }
        XCTAssertGreaterThan(apart.max() ?? 0, 40, "the arms never got out of step")
    }

    /// Five moves, each of them actually reached, or the routine is one move
    /// with four names.
    func testTheRoutineRunsThroughEveryMove() {
        var seen: Set<Dance.Move> = []
        for step in stride(from: 0.0, through: Dance.duration, by: 0.1) {
            seen.insert(Dance.move(at: step))
        }
        XCTAssertEqual(seen.count, Dance.Move.allCases.count)
    }

    /// It loops rather than ending, so the same moment of the second time
    /// through is the same pose.
    func testItLoopsFromTheTop() {
        for step in stride(from: 0.0, through: Dance.duration, by: 0.25) {
            XCTAssertEqual(Dance.move(at: step), Dance.move(at: step + Dance.duration))
        }
    }

    /// The whole rainbow, and back to where it started, inside one time through.
    func testTheHueRunsRightRound() {
        let hues = stride(from: 0.0, through: Dance.duration, by: 0.1).map { Dance.frame(at: $0).hue }
        XCTAssertLessThan(hues.min() ?? 1, 0.06)
        XCTAssertGreaterThan(hues.max() ?? 0, 0.94)
        for hue in hues {
            XCTAssertTrue((0...1).contains(hue), "\(hue) is not on the wheel")
        }
    }

    /// Bright and saturated, or a dark pet on a light desktop turns to mud.
    func testTheColoursStayVivid() {
        let colour = Dance.colour(at: 0.4)
        XCTAssertGreaterThan(colour.saturation, 0.6)
        XCTAssertGreaterThan(colour.brightness, 0.85)
    }
}
