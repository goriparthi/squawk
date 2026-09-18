import XCTest
@testable import SquawkCore

final class TrotTests: XCTestCase {
    /// A trot moves diagonal pairs together. Moving the legs on one side
    /// together is a pace, and moving all four together is a pantomime horse.
    func testDiagonalPairsMoveTogether() {
        for step in stride(from: 0.0, through: 1.0, by: 0.02) {
            let pose = Trot.pose(phase: step)
            // Front left rides the arm channel, hind right the leg channel.
            let frontLeft = pose.leftShoulder - Trot.frontStance
            let hindRight = pose.rightHip - Trot.hindStance
            XCTAssertEqual(frontLeft, hindRight, accuracy: 0.001,
                           "the diagonal pair fell out of step at \(step)")
        }
    }

    /// The two legs on the same side are half a stride apart, which is the
    /// other half of what makes it a trot.
    func testTheSameSideIsOutOfPhase() {
        let samples = stride(from: 0.0, to: 1.0, by: 0.01).map { Trot.pose(phase: $0) }
        let agreement = samples.reduce(0.0) {
            $0 + ($1.leftShoulder - Trot.frontStance) * ($1.leftHip - Trot.hindStance)
        }
        XCTAssertLessThan(agreement, 0, "front and hind on one side moved together")
    }

    /// Front legs fold forward, hind legs fold back. Getting this the wrong way
    /// round is what makes a robot dog look like a table.
    func testTheJointsFoldTheRightWay() {
        for step in stride(from: 0.0, through: 1.0, by: 0.02) {
            let pose = Trot.pose(phase: step)
            XCTAssertLessThan(pose.leftElbow, 0, "a front leg folded backward at \(step)")
            XCTAssertGreaterThan(pose.leftKnee, 0, "a hind leg folded forward at \(step)")
        }
    }

    /// Four legs rise and fall twice a stride, once over each pair.
    func testTheBackRisesTwicePerStride() {
        let samples = stride(from: 0.0, to: 1.0, by: 0.005).map { Trot.pose(phase: $0).bob }
        var peaks = 0
        for index in 1..<(samples.count - 1)
        where samples[index] > samples[index - 1] && samples[index] >= samples[index + 1] {
            peaks += 1
        }
        XCTAssertEqual(peaks, 2)
    }

    /// The head stays level while the body works underneath it, which is the
    /// one thing that makes a walking quadruped look alive rather than driven.
    func testTheHeadCountersTheBody() {
        for step in stride(from: 0.05, through: 0.95, by: 0.05) {
            let pose = Trot.pose(phase: step)
            guard pose.bob > 0.005 else { continue }
            XCTAssertLessThan(pose.headPitch, 0, "the head rode the body at \(step)")
        }
    }

    /// Standing still is not standing to attention: an animal keeps a bend in
    /// every leg. And standing is the walk with nothing turned up, so the two
    /// cannot disagree about where a leg goes.
    func testItStandsWithItsLegsBent() {
        let stance = Trot.standing()
        XCTAssertEqual(stance, Trot.pose(phase: 0.63, effort: 0),
                       "standing and a stopped walk should be the same pose")
        XCTAssertNotEqual(stance.leftElbow, 0)
        XCTAssertNotEqual(stance.leftKnee, 0)
        XCTAssertLessThan(stance.leftElbow, 0)
        XCTAssertGreaterThan(stance.leftKnee, 0)
    }

    /// No effort is standing square, so a trot can slow to a stop rather than
    /// switching off, exactly as the biped's stride does.
    func testNoEffortIsStandingStill() {
        let still = Trot.pose(phase: 0.41, effort: 0)
        XCTAssertEqual(still.bob, 0, accuracy: 0.0001)
        XCTAssertEqual(still.leftShoulder, Trot.frontStance, accuracy: 0.0001)
        XCTAssertEqual(still.leftHip, Trot.hindStance, accuracy: 0.0001)
    }

    /// The cast carries both shapes, and a build is not a colourway.
    func testTheCastHasBothBuilds() {
        XCTAssertTrue(Cast.all.contains { $0.build == .biped })
        XCTAssertTrue(Cast.all.contains { $0.build == .quadruped })
        XCTAssertEqual(Set(Cast.all.map(\.id)).count, Cast.all.count, "duplicate ids")
    }
}
