import XCTest
@testable import SquawkCore

final class TummyRubTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    /// Crossing the body on the way somewhere else is not affection.
    func testOneSweepIsNotARub() {
        var rub = TummyRub()
        for step in stride(from: 0.0, through: 200.0, by: 10.0) {
            XCTAssertFalse(rub.track(x: CGFloat(step), at: start))
        }
    }

    func testBackAndForthIsARub() {
        var rub = TummyRub()
        var fired = false
        var now = start
        for (index, x) in sweep(times: 4).enumerated() {
            now = start.addingTimeInterval(Double(index) * 0.05)
            if rub.track(x: x, at: now) { fired = true }
        }
        XCTAssertTrue(fired, "four passes should read as a rub")
    }

    /// Otherwise a pointer resting on the body all afternoon eventually adds up.
    func testReversalsHaveToBeCloseTogether() {
        var rub = TummyRub()
        var fired = false
        for (index, x) in sweep(times: 6).enumerated() {
            let now = start.addingTimeInterval(Double(index) * TummyRub.window)
            if rub.track(x: x, at: now) { fired = true }
        }
        XCTAssertFalse(fired, "slow wandering is not a rub")
    }

    func testJitterBelowTheThresholdIsIgnored() {
        var rub = TummyRub()
        var now = start
        for index in 0..<200 {
            now = start.addingTimeInterval(Double(index) * 0.01)
            let wobble = CGFloat(index % 2) * (TummyRub.threshold - 1)
            XCTAssertFalse(rub.track(x: wobble, at: now))
        }
    }

    /// Leaving the tummy ends it, so two half rubs minutes apart do not join up.
    func testLeavingStartsOver() {
        var rub = TummyRub()
        var fired = false
        for (index, x) in sweep(times: 2).enumerated() {
            if rub.track(x: x, at: start.addingTimeInterval(Double(index) * 0.05)) { fired = true }
        }
        rub.reset()
        for (index, x) in sweep(times: 2).enumerated() {
            if rub.track(x: x, at: start.addingTimeInterval(1 + Double(index) * 0.05)) { fired = true }
        }
        XCTAssertFalse(fired)
    }

    /// Positions for a pointer going back and forth across the belly.
    private func sweep(times: Int) -> [CGFloat] {
        var points: [CGFloat] = []
        for pass in 0..<times {
            let forward = pass.isMultiple(of: 2)
            let range = stride(from: 0.0, through: 60.0, by: 15.0).map { CGFloat($0) }
            points += forward ? range : range.reversed()
        }
        return points
    }
}

final class FortuneTests: XCTestCase {
    func testThereAreEnoughToNotRepeatQuickly() {
        XCTAssertGreaterThan(Fortune.all.count, 30)
        XCTAssertEqual(Set(Fortune.all).count, Fortune.all.count, "duplicates")
    }

    func testItNeverRepeatsTheOneJustSaid() {
        var generator = SystemRandomNumberGenerator()
        var previous = Fortune.all[0]
        for _ in 0..<200 {
            let next = Fortune.next(after: previous, using: &generator)
            XCTAssertNotEqual(next, previous)
            previous = next
        }
    }

    /// The house style, and these are the most user facing strings in the app.
    func testNoneCarryAnEmDash() {
        for line in Fortune.all {
            XCTAssertFalse(line.contains("\u{2014}"), line)
            XCTAssertFalse(line.contains("\u{2013}"), line)
            XCTAssertFalse(line.isEmpty)
            XCTAssertLessThan(line.count, 90, "too long for the bubble: \(line)")
        }
    }
}

final class AngriestPoseTests: XCTestCase {
    /// The last rung of angry is the only reaction addressed to you rather than
    /// merely worn: it points. Sideways flapping read as flustered, and both
    /// arms thrown up read as a tantrum aimed at nobody.
    func testTheLastLevelOfMadPointsAtYou() {
        let pose = BodyPose.pose(for: .dizzy)
        XCTAssertEqual(pose.right.grip, .point, "should have a finger out")
        XCTAssertGreaterThan(pose.right.shoulder, 60, "the arm should be up and out")
        XCTAssertLessThan(pose.left.shoulder, 60, "the other should be down")
        XCTAssertGreaterThan(pose.lean, 0, "leaning in at you, not away")
        XCTAssertGreaterThan(pose.liveliness, 2, "still shaking with it")
    }

    /// Pointing carries the arm out of the plane the others swing in, which is
    /// the whole reason `Pose3D.point` exists.
    func testPointingSwingsTheArmForward() {
        XCTAssertGreaterThan(BodyPose.pose(for: .dizzy).pose3D().point, 40)
        // And nothing else does, or every raised arm would jab at you.
        for face in FaceExpression.allCases where face != .dizzy {
            XCTAssertEqual(BodyPose.pose(for: face).pose3D().point, 0, face.rawValue)
        }
    }
}
