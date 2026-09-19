import XCTest
@testable import SquawkCore

final class MoodTests: XCTestCase {
    private let soon = Date(timeIntervalSince1970: 1_700_000_000)

    func testTheNudgeOutranksRestButNeverWork() {
        XCTAssertEqual(Mood.decide(MoodState(restless: true)).expression, .restless)
        let busy = Mood.decide(MoodState(waiting: 1, awaitingDecision: true, restless: true, selected: true))
        XCTAssertEqual(busy.expression, .alert)
        XCTAssertTrue(busy.showsCard)
    }

    func testAFortuneYieldsToWorkAndWellnessDoesNot() {
        let fortune = Speech(kind: .fortune, face: .happy, until: soon)
        let wellness = Speech(kind: .wellness, face: .curious, until: soon, holdsStill: true)
        XCTAssertEqual(Mood.decide(MoodState(waiting: 1, awaitingDecision: true, speech: fortune)).expression, .alert)
        let looked = Mood.decide(MoodState(waiting: 1, awaitingDecision: true, speech: wellness))
        XCTAssertEqual(looked.expression, .curious)
        XCTAssertFalse(looked.grooves)
        XCTAssertTrue(looked.showsBubble)
    }

    /// The bug this replaces: a refusal pointed at you was blended halfway
    /// back to a wiggle, and its face came from a poke timer, not the speech.
    func testARefusalHoldsStillAndKeepsItsFace() {
        let refusal = Speech(kind: .refusal, face: .dizzy, until: soon, holdsStill: true)
        let decision = Mood.decide(MoodState(speech: refusal, hearingMusic: true))
        XCTAssertEqual(decision.expression, .dizzy)
        XCTAssertFalse(decision.grooves)
    }

    func testMusicAloneGroovesOnceAReactionHasPassed() {
        XCTAssertEqual(Mood.decide(MoodState(hearingMusic: true)).expression, .grooving)
        let justPoked = MoodState(hearingMusic: true, lastEvent: .poked(.wink), eventAge: 0.2)
        XCTAssertEqual(Mood.decide(justPoked).expression, .wink)
        let pokedAWhileAgo = MoodState(hearingMusic: true, lastEvent: .poked(.wink), eventAge: 5)
        XCTAssertEqual(Mood.decide(pokedAWhileAgo).expression, .grooving)
        // The flat dial has no body to groove with.
        XCTAssertEqual(Mood.decide(MoodState(hearingMusic: true, modelled: false)).expression, .calm)
    }

    func testTheFlatDialSharesTheMiddleBetweenFaceAndCard() {
        let quiet = Mood.decide(MoodState(modelled: false, selected: true))
        XCTAssertTrue(quiet.showsFace)
        XCTAssertFalse(quiet.showsCard)
        let busy = Mood.decide(MoodState(waiting: 1, awaitingDecision: true, modelled: false, selected: true))
        XCTAssertFalse(busy.showsFace)
        XCTAssertTrue(busy.showsCard)
        XCTAssertFalse(busy.showsBubble)
    }

    func testTheBodyPaintsItsOwnFaceAndSpeaksFromTheBubble() {
        let busy = Mood.decide(MoodState(waiting: 2, awaitingDecision: true, selected: true))
        XCTAssertEqual(busy.expression, .urgent)
        XCTAssertFalse(busy.showsFace)
        XCTAssertTrue(busy.showsCard)
        XCTAssertTrue(busy.showsBubble)
    }
}
