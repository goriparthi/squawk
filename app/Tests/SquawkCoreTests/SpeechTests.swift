import XCTest
@testable import SquawkCore

final class SpeechTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func speech(_ kind: Speech.Kind, for seconds: TimeInterval = 5) -> Speech {
        Speech(kind: kind, face: .happy, until: now.addingTimeInterval(seconds))
    }

    func testAHigherKindTakesTheSlotAtOnce() {
        var slot = Speaking()
        XCTAssertTrue(slot.say(speech(.fortune), at: now))
        XCTAssertTrue(slot.say(speech(.refusal), at: now))
        XCTAssertEqual(slot.speech(at: now)?.kind, .refusal)
    }

    func testALowerKindWaitsWhileAHigherOneIsUp() {
        var slot = Speaking()
        slot.say(speech(.refusal, for: 3), at: now)
        XCTAssertFalse(slot.say(speech(.fortune), at: now.addingTimeInterval(1)))
        XCTAssertEqual(slot.speech(at: now.addingTimeInterval(1))?.kind, .refusal)
        // Once the refusal has run its course the fortune is welcome.
        XCTAssertTrue(slot.say(speech(.fortune), at: now.addingTimeInterval(4)))
    }

    func testTheSameKindReplacesItself() {
        var slot = Speaking()
        slot.say(speech(.fortune, for: 7), at: now)
        XCTAssertTrue(slot.say(speech(.fortune, for: 9), at: now.addingTimeInterval(2)))
        // The later fortune's deadline is the one that counts.
        XCTAssertEqual(slot.speech(at: now.addingTimeInterval(8))?.kind, .fortune)
        XCTAssertNil(slot.speech(at: now.addingTimeInterval(9)))
    }

    func testAnExpiredSpeechIsGone() {
        var slot = Speaking()
        slot.say(speech(.wellness, for: 8), at: now)
        XCTAssertNotNil(slot.speech(at: now.addingTimeInterval(7.9)))
        XCTAssertNil(slot.speech(at: now.addingTimeInterval(8)))
    }

    func testStoppingOneKindLeavesAnother() {
        var slot = Speaking()
        slot.say(speech(.fortune), at: now)
        slot.stop(.wellness)
        XCTAssertEqual(slot.speech(at: now)?.kind, .fortune)
        slot.stop()
        XCTAssertNil(slot.speech(at: now))
    }

    func testOnlyWellnessSpeaksOverWork() {
        XCTAssertFalse(speech(.wellness).yieldsToWork)
        for kind in [Speech.Kind.nowPlaying, .fortune, .refusal] {
            XCTAssertTrue(speech(kind).yieldsToWork, "\(kind)")
        }
    }
}
