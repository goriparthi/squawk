import XCTest
@testable import SquawkCore

final class PetClickTests: XCTestCase {
    func testAClickOffThePetIsNothing() {
        XCTAssertEqual(PetClick.decide(onPet: false, onTummy: false, clicks: 1, moved: 0), .nothing)
    }

    func testADragIsNotAPoke() {
        XCTAssertEqual(PetClick.decide(onPet: true, onTummy: false, clicks: 1, moved: 12), .nothing)
    }

    /// Poking the head as fast as you like keeps poking; the click count is
    /// not a dance request anywhere but the tummy.
    func testRapidPokesOnTheHeadStayPokes() {
        for clicks in 1...5 {
            XCTAssertEqual(PetClick.decide(onPet: true, onTummy: false, clicks: clicks, moved: 1), .poke)
        }
    }

    func testTheTummyGigglesOnATapAndDancesOnTwo() {
        XCTAssertEqual(PetClick.decide(onPet: true, onTummy: true, clicks: 1, moved: 0), .giggle)
        XCTAssertEqual(PetClick.decide(onPet: true, onTummy: true, clicks: 2, moved: 0), .dance)
        XCTAssertEqual(PetClick.decide(onPet: true, onTummy: true, clicks: 3, moved: 0), .nothing)
    }
}

/// One motion meaning "you are in my way", which must be impossible to do by
/// accident while repositioning the pet.
final class ShoveTests: XCTestCase {
    func testAFastLongThrowIsAShove() {
        XCTAssertTrue(Shove.wasShoved(distance: 400, seconds: 0.2))
    }

    /// Placing a pet somewhere is slow, however far it travels.
    func testCarryingItAcrossTheScreenIsNotAShove() {
        XCTAssertFalse(Shove.wasShoved(distance: 900, seconds: 2.0))
    }

    /// And a quick twitch on the way to a click is not one either.
    func testAShortFlickIsNotAShove() {
        XCTAssertFalse(Shove.wasShoved(distance: Shove.distance - 1, seconds: 0.01))
    }

    func testBothTestsHaveToPass() {
        // Fast enough, not far enough.
        XCTAssertFalse(Shove.wasShoved(distance: 30, seconds: 0.01))
        // Far enough, not fast enough.
        XCTAssertFalse(Shove.wasShoved(distance: 200, seconds: 1.0))
        // Both.
        XCTAssertTrue(Shove.wasShoved(distance: 200, seconds: 0.15))
    }

    func testAMotionWithNoTimeIsNotAShove() {
        XCTAssertFalse(Shove.wasShoved(distance: 500, seconds: 0))
        XCTAssertFalse(Shove.wasShoved(distance: 500, seconds: -1))
    }

    func testItIsExactlyAtTheThreshold() {
        XCTAssertTrue(Shove.wasShoved(distance: Shove.distance,
                                      seconds: Shove.distance / Shove.speed))
        XCTAssertFalse(Shove.wasShoved(distance: Shove.distance,
                                       seconds: Shove.distance / Shove.speed * 1.01))
    }

    /// It is a "get out of the way", not an off switch. The menu has one.
    func testItComesBackOnItsOwn() {
        XCTAssertGreaterThan(Shove.staysAwayFor, 60)
        XCTAssertLessThanOrEqual(Shove.staysAwayFor, 30 * 60)
    }
}
