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
