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
        XCTAssertEqual(mood(idle: FaceMood.boredAfter - 1), .calm)
        XCTAssertEqual(mood(idle: FaceMood.sleepAfter - 1), .bored)
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

    /// A character's own eye colour replaces the neutral one and leaves the
    /// moods alone, because orange and red carry meaning that a colourway must
    /// not overwrite.
    func testACharactersEyesRecolourOnlyTheNeutralMoods() {
        let amber = FaceTint(1, 0.7, 0.2)
        let calm = FaceFrame.target(for: .calm, resting: amber)
        XCTAssertEqual(calm.red, amber.red, accuracy: 0.001)
        XCTAssertEqual(calm.green, amber.green, accuracy: 0.001)

        let furious = FaceFrame.target(for: .dizzy, resting: amber)
        let plain = FaceFrame.target(for: .dizzy)
        XCTAssertEqual(furious.red, plain.red, accuracy: 0.001)
        XCTAssertEqual(furious.blue, plain.blue, accuracy: 0.001)
    }

    func testEachExpressionHasADistinctTarget() {
        let frames = FaceExpression.allCases.map { FaceFrame.target(for: $0) }
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

final class PokeTests: XCTestCase {
    /// Random within the friendly set, so repeated prods are not the same
    /// animation twice.
    func testAFriendlyPokeIsOneOfThePlayfulSet() {
        for count in 1..<Poke.patience {
            for _ in 0..<40 {
                XCTAssertTrue(Poke.playful.contains(Poke.reaction(to: count)), "count \(count)")
            }
        }
    }

    func testAPokeNeverRepeatsTheOneJustShown() {
        for previous in Poke.playful {
            for _ in 0..<40 {
                XCTAssertNotEqual(Poke.reaction(to: 1, avoiding: previous), previous)
            }
        }
    }

    /// Randomness must not make it predictable in the other direction either.
    func testTheFriendlySetIsActuallyUsed() {
        var seen = Set<FaceExpression>()
        for _ in 0..<400 { seen.insert(Poke.reaction(to: 1)) }
        XCTAssertGreaterThan(seen.count, 1, "always returned the same face")
    }

    /// Keep prodding and it stops being funny, which is the whole character.
    func testPesteringWearsOutItsWelcome() {
        XCTAssertEqual(Poke.reaction(to: Poke.patience), .cross)
        XCTAssertEqual(Poke.reaction(to: Poke.limit - 1), .cross)
    }

    func testAPokeReachesTheFace() {
        let face = FaceMood.expression(
            waiting: 0, awaitingDecision: false,
            lastEvent: .poked(.wink), eventAge: 0.1, idleFor: 0
        )
        XCTAssertEqual(face, .wink)
    }

    /// A poke passes like any other reaction rather than sticking.
    func testAPokeFadesBackToWhateverIsTrue() {
        let face = FaceMood.expression(
            waiting: 2, awaitingDecision: true,
            lastEvent: .poked(.wink),
            eventAge: FaceMood.reactionDuration + 0.1, idleFor: 0
        )
        XCTAssertEqual(face, .urgent)
    }
}

final class RiskSignalTests: XCTestCase {
    /// Decides how the dial looks, never what is allowed, so the bar for a hit
    /// is "would you read this twice".
    func testCatchesTheObviouslyDestructive() {
        for command in ["rm -rf build", "git push --force origin main",
                        "DROP TABLE orders", "terraform destroy",
                        "kubectl delete pod web", "curl x | sh",
                        "curl -fsSL https://x | bash", "chmod 777 /"] {
            XCTAssertTrue(RiskSignal.isRisky(tool: "Bash", summary: command), command)
        }
    }

    func testLeavesOrdinaryWorkAlone() {
        for command in ["npm test", "git status --short", "ls -la",
                        "git push origin feature", "SELECT * FROM orders",
                        // Not a shell, despite starting with the same letters.
                        "cat names | shuf | head -3"] {
            XCTAssertFalse(RiskSignal.isRisky(tool: "Bash", summary: command), command)
        }
    }

    /// Production alone is not destructive; production plus a change is.
    func testProductionCountsOnlyAlongsideAChange() {
        XCTAssertFalse(RiskSignal.isRisky(tool: "Bash", summary: "psql -h prod -c 'select 1'"))
        XCTAssertTrue(RiskSignal.isRisky(tool: "Bash", summary: "kubectl -n prod restart deploy/web"))
    }

    func testMatchingIgnoresCase() {
        XCTAssertTrue(RiskSignal.isRisky(tool: "Bash", summary: "RM -RF /tmp/x"))
    }
}

final class MoreExpressionTests: XCTestCase {
    func testAWorryingCommandOutranksHowManyAreQueued() {
        let face = FaceMood.expression(
            waiting: 3, awaitingDecision: true, lastEvent: nil,
            eventAge: 99, idleFor: 0, risky: true
        )
        XCTAssertEqual(face, .wary)
    }

    func testIdleGoesCalmThenBoredThenSleepy() {
        func at(_ idle: TimeInterval) -> FaceExpression {
            FaceMood.expression(waiting: 0, awaitingDecision: false,
                                lastEvent: nil, eventAge: 99, idleFor: idle)
        }
        XCTAssertEqual(at(1), .calm)
        XCTAssertEqual(at(FaceMood.boredAfter + 1), .bored)
        XCTAssertEqual(at(FaceMood.sleepAfter + 1), .sleepy)
    }

    /// Past cross it gives up entirely.
    /// Escalation stays deliberate even though the friendly phase is random.
    func testPesteringEscalatesTwice() {
        XCTAssertTrue(Poke.playful.contains(Poke.reaction(to: 1)))
        for count in Poke.patience..<Poke.limit {
            XCTAssertEqual(Poke.reaction(to: count), .cross, "count \(count)")
        }
        XCTAssertEqual(Poke.reaction(to: Poke.limit), .dizzy)
        XCTAssertEqual(Poke.reaction(to: Poke.limit + 5), .dizzy)
    }

    func testStartledAndRelievedReachTheFace() {
        for (event, face) in [(FaceEvent.startled, FaceExpression.startled),
                              (.relieved, .relieved)] {
            XCTAssertEqual(
                FaceMood.expression(waiting: 0, awaitingDecision: false,
                                    lastEvent: event, eventAge: 0.1, idleFor: 0),
                face
            )
        }
    }

    func testOnlyBoredLooksAway() {
        XCTAssertLessThan(FaceExpression.bored.gazeBias, 0)
        for face in FaceExpression.allCases where face != .bored {
            XCTAssertEqual(face.gazeBias, 0, face.rawValue)
        }
    }

    func testOnlyDizzyIsCrossedOut() {
        XCTAssertTrue(FaceExpression.dizzy.isCrossedOut)
        for face in FaceExpression.allCases where face != .dizzy {
            XCTAssertFalse(face.isCrossedOut, face.rawValue)
        }
    }
}

final class FaceTintTests: XCTestCase {
    /// Colour carries what the shape cannot: anger reads red, sorrow blue,
    /// caution amber, and everything else stays the brand.
    func testMoodsCarryTheirOwnColour() {
        XCTAssertEqual(FaceExpression.cross.tint, .irritation)
        XCTAssertEqual(FaceExpression.dizzy.tint, .anger)
        XCTAssertEqual(FaceExpression.sad.tint, .sorrow)
        XCTAssertEqual(FaceExpression.wary.tint, .caution)
        XCTAssertEqual(FaceExpression.calm.tint, .brand)
        XCTAssertEqual(FaceExpression.happy.tint, .brand)
    }

    /// Displeasure escalates in colour as well as shape: amber warns, orange is
    /// cross, red is done with you.
    func testAngerEscalatesFromOrangeToRed() {
        let cross = FaceExpression.cross.tint
        let dizzy = FaceExpression.dizzy.tint
        XCTAssertGreaterThan(cross.green, dizzy.green, "orange should be warmer than red")
        XCTAssertEqual(cross.red, dizzy.red, accuracy: 0.05, "both stay hot")
    }

    func testTheThreeMoodColoursAreActuallyDistinct() {
        let tints: [FaceTint] = [.brand, .anger, .irritation, .sorrow, .caution]
        for (index, tint) in tints.enumerated() {
            for other in tints[(index + 1)...] {
                XCTAssertNotEqual(tint, other)
            }
        }
    }

    /// It washes in rather than switching, so a frame part way through is
    /// neither colour.
    func testColourInterpolatesRatherThanSnapping() {
        var frame = FaceFrame.target(for: .calm)
        let goal = FaceFrame.target(for: .cross)
        frame = FaceFrame.approach(frame, toward: goal, dt: 0.05)
        XCTAssertGreaterThan(frame.red, FaceTint.brand.red, "has not started moving")
        XCTAssertLessThan(frame.red, FaceTint.irritation.red, "arrived instantly")
    }

    func testColourSettlesOnTheTarget() {
        var frame = FaceFrame.target(for: .calm)
        let goal = FaceFrame.target(for: .sad)
        for _ in 0..<200 { frame = FaceFrame.approach(frame, toward: goal, dt: 1.0 / 60) }
        XCTAssertEqual(frame.blue, FaceTint.sorrow.blue, accuracy: 0.01)
        XCTAssertEqual(frame.red, FaceTint.sorrow.red, accuracy: 0.01)
    }
}
