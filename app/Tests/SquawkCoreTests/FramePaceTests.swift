import XCTest
@testable import SquawkCore

final class FramePaceTests: XCTestCase {
    func testStandingRestsAtThirty() {
        XCTAssertEqual(FramePace.rate(moving: false, listening: false, displayMax: 120), 30)
    }

    /// The whole point: a track no longer pins the display maximum.
    func testListeningStopsAtSixty() {
        XCTAssertEqual(FramePace.rate(moving: false, listening: true, displayMax: 120), 60)
    }

    func testMovingTakesTheDisplayMaximum() {
        XCTAssertEqual(FramePace.rate(moving: true, listening: false, displayMax: 120), 120)
        XCTAssertEqual(FramePace.rate(moving: true, listening: true, displayMax: 120), 120)
    }

    /// A 60Hz panel is never asked for more than it has.
    func testNeverAsksForMoreThanTheDisplayHas() {
        XCTAssertEqual(FramePace.rate(moving: true, listening: false, displayMax: 60), 60)
        XCTAssertEqual(FramePace.rate(moving: false, listening: true, displayMax: 60), 60)
        XCTAssertEqual(FramePace.rate(moving: false, listening: false, displayMax: 24), 24)
    }
}
