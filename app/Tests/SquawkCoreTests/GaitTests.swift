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

    /// Arms swing against their own leg. Swinging with it is a march.
    func testTheArmsOpposeTheLegs() {
        for step in stride(from: 0.05, to: 1.0, by: 0.05) {
            let moment = Gait.stride(phase: step)
            guard abs(moment.left.hip) > 2 else { continue }
            XCTAssertLessThan(moment.left.hip * moment.leftArm, 0,
                              "left arm and left leg moved together at \(step)")
        }
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
        let full = Gait.phase(at: 1 / Gait.cadence)
        XCTAssertLessThan(full, 0.0001, "one stride should land back at the start")
        XCTAssertLessThan(Gait.phase(at: 99), 1)
    }
}

final class DanceTests: XCTestCase {
    /// An arm past straight up carries on round and comes back down the other
    /// side, which reads as a joint giving way.
    func testArmsStayWithinTheirJoint() {
        for step in stride(from: 0.0, through: Dance.duration, by: 0.02) {
            let moment = Dance.frame(at: step)
            XCTAssertLessThanOrEqual(moment.leftArm, 170, "at \(step)")
            XCTAssertLessThanOrEqual(moment.rightArm, 170, "at \(step)")
            XCTAssertGreaterThan(moment.leftArm, 0, "at \(step)")
        }
    }

    /// Both arms doing the same thing is a stretch, not a dance.
    func testTheArmsTakeTurns() {
        let apart = stride(from: 0.0, through: 4.0, by: 0.05)
            .map { abs(Dance.frame(at: $0).leftArm - Dance.frame(at: $0).rightArm) }
        XCTAssertGreaterThan(apart.max() ?? 0, 40, "the arms never got out of step")
    }

    /// The whole rainbow, and back to where it started, inside one dance.
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
