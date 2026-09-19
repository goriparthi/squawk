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

    func testTheTummyTakesADoubleTapAndNothingElse() {
        XCTAssertEqual(PetClick.decide(onPet: true, onTummy: true, clicks: 1, moved: 0), .nothing)
        XCTAssertEqual(PetClick.decide(onPet: true, onTummy: true, clicks: 2, moved: 0), .dance)
        XCTAssertEqual(PetClick.decide(onPet: true, onTummy: true, clicks: 3, moved: 0), .nothing)
    }
}
