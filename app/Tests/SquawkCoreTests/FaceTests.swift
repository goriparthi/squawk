import XCTest
@testable import SquawkCore

final class FaceMoodTests: XCTestCase {
    private func mood(
        waiting: Int = 0,
        decision: Bool = true,
        event: FaceEvent? = nil,
        age: TimeInterval = 0,
        idle: TimeInterval = 0
    ) -> FaceExpression {
        FaceMood.expression(
            waiting: waiting, awaitingDecision: decision,
            lastEvent: event, eventAge: age, idleFor: idle
        )
    }

    func testRestingFaceIsCalm() {
        XCTAssertEqual(mood(), .calm)
    }

    func testEyesGetHeavyAfterALongQuietSpell() {
        XCTAssertEqual(mood(idle: FaceMood.sleepAfter - 1), .calm)
        XCTAssertEqual(mood(idle: FaceMood.sleepAfter + 1), .sleepy)
    }

    func testOneDecisionIsAlertAndSeveralAreUrgent() {
        XCTAssertEqual(mood(waiting: 1), .alert)
        XCTAssertEqual(mood(waiting: 3), .urgent)
    }

    /// A question is not a demand, so it reads as curious rather than urgent.
    func testSomethingWithNothingToDecideIsCurious() {
        XCTAssertEqual(mood(waiting: 1, decision: false), .curious)
        XCTAssertEqual(mood(waiting: 4, decision: false), .curious)
    }

    func testAnAnswerIsAcknowledgedBeforeTheRestingFaceReturns() {
        XCTAssertEqual(mood(event: .approved, age: 0.2), .happy)
        XCTAssertEqual(mood(event: .denied, age: 0.2), .cross)
        XCTAssertEqual(mood(event: .abandoned, age: 0.2), .sad)
    }

    func testAReactionGivesWayToTheStateUnderneath() {
        let old = FaceMood.reactionDuration + 0.1
        XCTAssertEqual(mood(event: .approved, age: old), .calm)
        XCTAssertEqual(mood(waiting: 2, event: .approved, age: old), .urgent)
    }

    /// A reaction outranks a waiting request, so answering one of several still
    /// acknowledges the answer rather than snapping straight back to urgent.
    func testAReactionOutranksWhatIsStillWaiting() {
        XCTAssertEqual(mood(waiting: 2, event: .approved, age: 0.1), .happy)
    }
}

final class FaceExpressionTests: XCTestCase {
    /// Sleepy is a lidded bar rather than a small eye, so the floor is low; the
    /// point is only that nothing collapses to nothing.
    func testEveryExpressionOpensToSomethingVisible() {
        for face in FaceExpression.allCases {
            XCTAssertGreaterThanOrEqual(face.openness, 0.15, face.rawValue)
            XCTAssertLessThanOrEqual(face.openness, 1.3, face.rawValue)
        }
        XCTAssertLessThan(FaceExpression.sleepy.openness, FaceExpression.calm.openness)
    }

    /// The eye carries the slant now, and the two feelings tilt opposite ways.
    func testDispleasureAndSadnessSlantOpposite() {
        XCTAssertLessThan(FaceExpression.cross.eyeTilt, 0)
        XCTAssertGreaterThan(FaceExpression.sad.eyeTilt, 0)
        XCTAssertEqual(FaceExpression.calm.eyeTilt, 0)
        XCTAssertEqual(FaceExpression.alert.eyeTilt, 0)
    }

    func testOnlyReactionsAreTransient() {
        XCTAssertTrue(FaceExpression.happy.isReaction)
        XCTAssertTrue(FaceExpression.cross.isReaction)
        XCTAssertTrue(FaceExpression.sad.isReaction)
        XCTAssertFalse(FaceExpression.calm.isReaction)
        XCTAssertFalse(FaceExpression.urgent.isReaction)
    }

    /// A mouth only where the eyes cannot carry it alone, and it curves the way
    /// the feeling does.
    func testMouthCurvesWithTheFeeling() {
        XCTAssertGreaterThan(FaceExpression.happy.mouthCurve, 0)
        XCTAssertLessThan(FaceExpression.sad.mouthCurve, 0)
        XCTAssertLessThan(FaceExpression.cross.mouthCurve, 0)
        XCTAssertFalse(FaceExpression.calm.hasMouth)
        XCTAssertFalse(FaceExpression.alert.hasMouth)
    }

    func testHappyIsDrawnAsAnArc() {
        XCTAssertTrue(FaceExpression.happy.isArc)
        XCTAssertFalse(FaceExpression.calm.isArc)
    }
}

final class FaceFlourishTests: XCTestCase {
    /// The asymmetry is the whole point of a wink; both eyes closing is a blink.
    func testOnlyTheWinkIsAsymmetric() {
        XCTAssertTrue(FaceExpression.wink.winksLeftEye)
        for face in FaceExpression.allCases where face != .wink {
            XCTAssertFalse(face.winksLeftEye, face.rawValue)
        }
    }

    /// Brows only where the eye shape cannot carry it, which is delight. Two
    /// more strokes on an angry face just compete with the slant.
    func testBrowsOnlyWhereTheFeelingNeedsThem() {
        XCTAssertTrue(FaceExpression.happy.hasBrows)
        XCTAssertFalse(FaceExpression.cross.hasBrows)
        XCTAssertFalse(FaceExpression.calm.hasBrows)
    }

    func testOnlyDelightGetsTheTriangle() {
        XCTAssertTrue(FaceExpression.happy.mouthIsTriangle)
        XCTAssertFalse(FaceExpression.sad.mouthIsTriangle)
        XCTAssertTrue(FaceExpression.sad.hasMouth)
    }

    /// A wink passes like any other reaction rather than sticking.
    func testWinkIsTransient() {
        XCTAssertTrue(FaceExpression.wink.isReaction)
    }

}

final class FaceFrameTests: XCTestCase {
    /// Frame-rate independence: the same elapsed time must land in the same
    /// place whether it arrived as one tick or many.
    func testApproachIsFrameRateIndependent() {
        let goal = FaceFrame.target(for: .urgent)
        var coarse = FaceFrame()
        coarse = FaceFrame.approach(coarse, toward: goal, dt: 0.1)

        var fine = FaceFrame()
        for _ in 0..<10 { fine = FaceFrame.approach(fine, toward: goal, dt: 0.01) }

        XCTAssertEqual(coarse.openness, fine.openness, accuracy: 0.01)
    }

    func testApproachConvergesRatherThanOvershooting() {
        let goal = FaceFrame.target(for: .happy)
        var frame = FaceFrame()
        for _ in 0..<200 { frame = FaceFrame.approach(frame, toward: goal, dt: 1.0 / 60) }
        XCTAssertTrue(frame.isNear(goal), "did not settle on the target")
        XCTAssertLessThanOrEqual(frame.squint, 1.0001, "overshot")
    }

    func testAZeroStepChangesNothing() {
        let start = FaceFrame.target(for: .calm)
        let after = FaceFrame.approach(start, toward: FaceFrame.target(for: .cross), dt: 0)
        XCTAssertTrue(after.isNear(start))
    }

    func testEachExpressionHasADistinctTarget() {
        let frames = FaceExpression.allCases.map(FaceFrame.target(for:))
        for (index, frame) in frames.enumerated() {
            for other in frames[(index + 1)...] {
                XCTAssertFalse(frame.isNear(other), "two expressions render identically")
            }
        }
    }
}

final class BlinkTests: XCTestCase {
    func testBlinkOpensAndClosesAndReturns() {
        XCTAssertEqual(Blink.openness(at: 0), 1, accuracy: 0.01)
        XCTAssertLessThan(Blink.openness(at: Blink.duration * 0.4), 0.15)
        XCTAssertEqual(Blink.openness(at: Blink.duration), 1, accuracy: 0.01)
    }

    /// Outside the blink the eye is simply open, so a stale clock cannot leave
    /// the face shut.
    func testOutsideTheBlinkTheEyeIsOpen() {
        XCTAssertEqual(Blink.openness(at: -1), 1)
        XCTAssertEqual(Blink.openness(at: Blink.duration + 5), 1)
    }

    /// Shuts faster than it opens, the way an eyelid does.
    func testItShutsFasterThanItOpens() {
        let shutting = Blink.openness(at: Blink.duration * 0.2)
        let opening = Blink.openness(at: Blink.duration * 0.8)
        XCTAssertLessThan(shutting, 0.9)
        XCTAssertGreaterThan(opening, 0.5)
    }

    func testOpennessNeverLeavesItsRange() {
        var t = 0.0
        while t <= Blink.duration {
            let value = Blink.openness(at: t)
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1.001)
            t += 0.005
        }
    }
}
