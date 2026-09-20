import XCTest
@testable import SquawkCore

final class WellnessTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 18,
                                           hour: hour, minute: minute))!
    }

    /// A pet that starts giving advice the moment you sit down has not earned
    /// the right to yet.
    func testNothingIsDueUntilYouHaveSettledIn() {
        let state = Wellness.State(startedAt: at(9, 0))
        XCTAssertNil(Wellness.due(state, now: at(9, 5), calendar: calendar))
        XCTAssertNil(Wellness.due(state, now: at(9, 11), calendar: calendar))
        XCTAssertNotNil(Wellness.due(state, now: at(9, 25), calendar: calendar))
    }

    /// The desk clock measured uptime, so a run started yesterday was still
    /// "3h at the desk" after a night's sleep.
    func testABreakStartsANewRun() {
        let state = Wellness.State(startedAt: at(9, 0), lastShown: [.eyes: at(11, 0)])
        let stillHere = Wellness.resumed(state, lastActive: at(12, 0), now: at(12, 30))
        XCTAssertEqual(stillHere.startedAt, at(9, 0))
        XCTAssertEqual(stillHere.lastShown[.eyes], at(11, 0))
        let back = Wellness.resumed(state, lastActive: at(12, 0), now: at(12, 46))
        XCTAssertEqual(back.startedAt, at(12, 46))
        XCTAssertNil(back.lastShown[.eyes], "a new run has said nothing yet")
        // And a new run has to settle in before it says anything.
        XCTAssertNil(Wellness.due(back, now: at(12, 50), calendar: calendar))
    }

    /// The bug this cost: `resumed` is correct, but fed a "last active" that
    /// only moves when someone touches the pet, it restarts the run on every
    /// check, the settle in period never elapses and nothing is ever due.
    /// Whatever the caller passes has to mean actually present.
    func testAStaleLastActiveStopsAnythingEverBeingDue() {
        var state = Wellness.State(startedAt: at(9, 0))
        let stale = at(9, 0)
        var now = at(9, 1)
        for _ in 0..<180 {
            state = Wellness.resumed(state, lastActive: stale, now: now)
            now = now.addingTimeInterval(60)
        }
        XCTAssertNil(Wellness.due(state, now: now, calendar: calendar),
                     "three hours of this and it still says nothing")

        // The same three hours, with someone actually there.
        var present = Wellness.State(startedAt: at(9, 0))
        now = at(9, 1)
        for _ in 0..<180 {
            present = Wellness.resumed(present, lastActive: now, now: now)
            now = now.addingTimeInterval(60)
        }
        XCTAssertNotNil(Wellness.due(present, now: now, calendar: calendar))
    }

    /// Anything waiting on an answer outranks every piece of this.
    func testItSaysNothingWhileSomethingIsWaiting() {
        let state = Wellness.State(startedAt: at(9, 0), busy: true)
        XCTAssertNil(Wellness.due(state, now: at(14, 0), calendar: calendar))
    }

    /// Two pieces of advice in the same minute is nagging, and nagging is what
    /// gets a feature switched off.
    func testItKeepsQuietAfterSpeaking() {
        let state = Wellness.State(startedAt: at(9, 0), lastAny: at(11, 0))
        XCTAssertNil(Wellness.due(state, now: at(11, 5), calendar: calendar))
        XCTAssertNotNil(Wellness.due(state, now: at(11, 20), calendar: calendar))
    }

    /// The most overdue one, so a long run does not always lead with whichever
    /// happens to have the shortest interval.
    func testItPicksWhateverIsMostOverdue() {
        var state = Wellness.State(startedAt: at(9, 0))
        // Eyes just went up, so at 11:00 water is the one that is furthest past
        // its interval.
        state.lastShown = [.eyes: at(10, 55), .posture: at(10, 40), .stretch: at(10, 30)]
        XCTAssertEqual(Wellness.due(state, now: at(11, 40), calendar: calendar), .water)
    }

    /// Once it is late, that is the only advice worth giving.
    func testLateOnItOnlySaysToStop() {
        let state = Wellness.State(startedAt: at(14, 0))
        XCTAssertEqual(Wellness.due(state, now: at(22, 30), calendar: calendar), .windDown)
    }

    /// Once a night, not every eight minutes until you go to bed.
    func testItSaysToStopOnlyOnce() {
        var state = Wellness.State(startedAt: at(14, 0))
        state.lastShown = [.windDown: at(22, 5)]
        state.lastAny = at(22, 5)
        XCTAssertNil(Wellness.due(state, now: at(23, 30), calendar: calendar))
    }

    /// Every prompt has to say something, and none of it can be an instruction
    /// it could check you followed, because it cannot.
    func testEveryPromptSaysSomethingShort() {
        for prompt in WellnessPrompt.allCases {
            XCTAssertFalse(prompt.message.isEmpty, prompt.rawValue)
            XCTAssertLessThan(prompt.message.count, 60, prompt.rawValue)
            XCTAssertGreaterThan(prompt.lifetime, 4, prompt.rawValue)
        }
    }

    /// The one with actual evidence behind it is the most frequent.
    func testTheEyeBreakIsTheMostFrequent() {
        let timed = WellnessPrompt.allCases.compactMap(\.everyMinutes)
        XCTAssertEqual(WellnessPrompt.eyes.everyMinutes, timed.min())
        XCTAssertEqual(WellnessPrompt.eyes.everyMinutes, 20)
    }

    func testItDescribesTimeAtTheDeskReadably() {
        XCTAssertEqual(Wellness.describe(0), "1m at the desk")
        XCTAssertEqual(Wellness.describe(45 * 60), "45m at the desk")
        XCTAssertEqual(Wellness.describe(3 * 3_600 + 20 * 60), "3h 20m at the desk")
    }
}

/// The nudge lands in the gap after a run, not in the middle of one.
final class BreakReminderGapTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let minutes = 30

    private func due(working: Bool, dueSince: Date?, lastNudge: Date? = nil) -> Bool {
        BreakReminder.isDue(
            minutes: minutes, now: now,
            lastInteraction: now.addingTimeInterval(-Double(minutes) * 60 - 5),
            lastNudge: lastNudge, working: working, dueSince: dueSince
        )
    }

    func testItFiresAtOnceWhenNothingIsRunning() {
        XCTAssertTrue(due(working: false, dueSince: nil))
    }

    /// A reminder landing mid run interrupts the thing you are watching, and
    /// the moment the run ends is the gap it was always meant to land in.
    func testItHoldsOffWhileTheAgentsAreWorking() {
        XCTAssertFalse(due(working: true, dueSince: now.addingTimeInterval(-60)))
    }

    func testItLandsTheMomentTheWorkStops() {
        XCTAssertTrue(due(working: false, dueSince: now.addingTimeInterval(-60)))
    }

    /// The point of a break reminder is the break. An agent churning for two
    /// hours is exactly the session where somebody needs telling to look up.
    func testTheHoldIsBounded() {
        XCTAssertTrue(due(
            working: true,
            dueSince: now.addingTimeInterval(-BreakReminder.waitsForAGapFor - 1)
        ))
    }

    func testWaitingIsShorterThanTheGapBetweenNudges() {
        XCTAssertLessThan(BreakReminder.waitsForAGapFor, BreakReminder.repeatAfter,
                          "it could hold past the point of being due again")
    }

    /// Holding for a gap must not become a way round the nagging limit.
    func testARecentNudgeStillSilencesIt() {
        XCTAssertFalse(due(working: false, dueSince: nil, lastNudge: now.addingTimeInterval(-60)))
        XCTAssertFalse(BreakReminder.isWaitingForAGap(
            minutes: minutes, now: now,
            lastInteraction: now.addingTimeInterval(-Double(minutes) * 60 - 5),
            lastNudge: now.addingTimeInterval(-60)
        ))
    }

    func testOffStaysOff() {
        XCTAssertFalse(BreakReminder.isDue(
            minutes: 0, now: now, lastInteraction: now.addingTimeInterval(-9_999),
            lastNudge: nil, working: false, dueSince: now.addingTimeInterval(-9_999)
        ))
        XCTAssertFalse(BreakReminder.isWaitingForAGap(
            minutes: 0, now: now, lastInteraction: now.addingTimeInterval(-9_999),
            lastNudge: nil
        ))
    }

    /// The clock only starts once it is genuinely due, or the hold would be
    /// measured from a moment that had nothing to do with it.
    func testItIsNotWaitingBeforeItIsDue() {
        XCTAssertFalse(BreakReminder.isWaitingForAGap(
            minutes: minutes, now: now,
            lastInteraction: now.addingTimeInterval(-60), lastNudge: nil
        ))
    }
}
