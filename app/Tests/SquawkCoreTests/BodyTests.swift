import XCTest
@testable import SquawkCore

final class BodyPoseTests: XCTestCase {
    /// Arms carry what a face at this size cannot, so every mood has to pose
    /// differently or the body is decoration.
    func testEveryMoodHasAPose() {
        var seen: [BodyPose] = []
        for face in FaceExpression.allCases {
            seen.append(BodyPose.pose(for: face))
        }
        XCTAssertEqual(seen.count, FaceExpression.allCases.count)
        XCTAssertGreaterThan(Set(seen.map(\.left.shoulder)).count, 4, "poses barely differ")
    }

    func testCallingYouOverRaisesBothArms() {
        for face in [FaceExpression.urgent, .startled, .happy] {
            let pose = BodyPose.pose(for: face)
            XCTAssertGreaterThan(pose.left.shoulder, 80, "\(face.rawValue) left")
            XCTAssertGreaterThan(pose.right.shoulder, 80, "\(face.rawValue) right")
        }
    }

    func testDejectionDropsTheArmsAndLeans() {
        let sad = BodyPose.pose(for: .sad)
        XCTAssertLessThan(sad.left.shoulder, ArmPose.resting.shoulder)
        XCTAssertGreaterThan(sad.lean, 0, "should slump forward")
        XCTAssertLessThan(sad.liveliness, 0.5, "should barely move")
    }

    /// A wink is asymmetric in the body too, or it reads as a stretch.
    func testAWinkIsLopsided() {
        let pose = BodyPose.pose(for: .wink)
        XCTAssertGreaterThan(abs(pose.right.shoulder - pose.left.shoulder), 40)
    }

    func testSleepBarelyMoves() {
        XCTAssertLessThan(BodyPose.pose(for: .sleepy).liveliness, 0.2)
        XCTAssertGreaterThan(BodyPose.pose(for: .dizzy).liveliness, 2)
    }

    /// Top heavy is what made it read as a head with a stand under it. The
    /// shell has to sit inside the body's width, not overhang it.
    

    /// Arms swing out from a body that is now broader, and a clipped hand is
    /// the sort of thing only a render shows.
    

    func testGeometryScalesWithTheHead() {
        let small = BodyGeometry.canvas(head: 150)
        let large = BodyGeometry.canvas(head: 480)
        XCTAssertLessThan(small.width, large.width)
        XCTAssertGreaterThan(small.width, 150, "arms need room beyond the head")
        XCTAssertGreaterThan(large.height, 480)
    }
}

final class BreakReminderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Off unless asked for. A tool that interrupts you uninvited has to be
    /// opted into.
    func testOffByDefault() {
        XCTAssertEqual(BreakReminder.defaultMinutes, 0)
        XCTAssertFalse(BreakReminder.isDue(
            minutes: 0, now: now, lastInteraction: now.addingTimeInterval(-9999), lastNudge: nil
        ))
    }

    func testDueAfterLongEnoughHeadsDown() {
        XCTAssertFalse(BreakReminder.isDue(
            minutes: 50, now: now,
            lastInteraction: now.addingTimeInterval(-49 * 60), lastNudge: nil
        ))
        XCTAssertTrue(BreakReminder.isDue(
            minutes: 50, now: now,
            lastInteraction: now.addingTimeInterval(-51 * 60), lastNudge: nil
        ))
    }

    /// Having nudged once, it waits before nudging again rather than nagging.
    func testItDoesNotNagOnEveryTick() {
        XCTAssertFalse(BreakReminder.isDue(
            minutes: 50, now: now,
            lastInteraction: now.addingTimeInterval(-60 * 60),
            lastNudge: now.addingTimeInterval(-60)
        ))
        XCTAssertTrue(BreakReminder.isDue(
            minutes: 50, now: now,
            lastInteraction: now.addingTimeInterval(-60 * 60),
            lastNudge: now.addingTimeInterval(-BreakReminder.repeatAfter - 1)
        ))
    }

    /// Never interacted with at all is not the same as ignored.
    func testNoInteractionYetIsNotDue() {
        XCTAssertFalse(BreakReminder.isDue(
            minutes: 50, now: now, lastInteraction: nil, lastNudge: nil
        ))
    }

    func testOnlyTheNudgeDemandsAttention() {
        XCTAssertTrue(FaceExpression.restless.demandsAttention)
        for face in FaceExpression.allCases where face != .restless {
            XCTAssertFalse(face.demandsAttention, face.rawValue)
        }
    }
}

final class EntranceTests: XCTestCase {
    func testWalksFromOffscreenToInPlace() {
        XCTAssertEqual(Entrance.progress(at: 0), 0, accuracy: 0.001)
        XCTAssertEqual(Entrance.progress(at: Entrance.duration), 1, accuracy: 0.001)
        XCTAssertGreaterThan(Entrance.progress(at: Entrance.duration / 2), 0.4)
    }

    func testItSettlesRatherThanStoppingDead() {
        // A small overshoot is what makes it look walked rather than slid.
        let peak = stride(from: 0.0, through: Entrance.duration, by: 0.01)
            .map(Entrance.progress(at:)).max() ?? 0
        XCTAssertGreaterThan(peak, 1.0)
        XCTAssertLessThan(peak, 1.12, "overshoot should be a nudge, not a bounce")
    }

    /// It comes in from whichever edge it is closest to, so it never crosses the
    /// whole screen to arrive.
    func testItEntersFromTheNearestEdge() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let nearRight = CGRect(x: 900, y: 400, width: 80, height: 80)
        XCTAssertGreaterThan(Entrance.offset(for: nearRight, in: visible).width, 0)

        let nearLeft = CGRect(x: 10, y: 400, width: 80, height: 80)
        XCTAssertLessThan(Entrance.offset(for: nearLeft, in: visible).width, 0)

        let nearBottom = CGRect(x: 460, y: 5, width: 80, height: 80)
        XCTAssertLessThan(Entrance.offset(for: nearBottom, in: visible).height, 0)
    }
}

final class BodySurfaceTests: XCTestCase {
    /// An arm rooted at the egg's widest x sits outside the silhouette at
    /// shoulder height, which is what made the hands look detached.
    func testTheEggHasTaperedByTheShoulder() {
        let atShoulder = BodyGeometry.halfWidthFraction(atFractionBelowTop: 0.30)
        XCTAssertLessThan(atShoulder, 1.0, "should be narrower than the widest point")
        XCTAssertGreaterThan(atShoulder, 0.7, "but not a spike")
    }

    func testItIsWidestAtTheWidestPoint() {
        let atWidest = BodyGeometry.halfWidthFraction(
            atFractionBelowTop: 1 - BodyGeometry.widestAt
        )
        XCTAssertEqual(atWidest, 1.0, accuracy: 0.001)
    }

    func testItNarrowsMonotonicallyTowardTheTop() {
        var previous = 1.0
        for step in stride(from: 0.55, through: 0.05, by: -0.05) {
            let width = BodyGeometry.halfWidthFraction(atFractionBelowTop: CGFloat(step))
            XCTAssertLessThanOrEqual(width, previous + 0.0001, "widened going up at \(step)")
            previous = Double(width)
        }
    }

    func testBelowTheWidestPointItStaysFull() {
        XCTAssertEqual(BodyGeometry.halfWidthFraction(atFractionBelowTop: 0.9), 1.0)
    }
}
