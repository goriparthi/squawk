import XCTest
@testable import SquawkCore

final class StrandedTests: XCTestCase {
    /// A laptop display, and a second one off to its right.
    private let built = CGRect(x: 0, y: 0, width: 1512, height: 945)
    private let second = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
    private let pet = CGSize(width: 200, height: 260)

    private func frame(x: CGFloat, y: CGFloat) -> CGRect {
        CGRect(origin: CGPoint(x: x, y: y), size: pet)
    }

    func testSittingOnTheDesktopIsFine() {
        XCTAssertFalse(Stranded.isStranded(frame(x: 600, y: 300), on: [built]))
    }

    /// Parking it half off an edge is a choice somebody made.
    func testParkedAgainstAnEdgeIsFine() {
        XCTAssertFalse(Stranded.isStranded(frame(x: 1412, y: 300), on: [built]),
                       "half off the right edge was treated as lost")
    }

    func testDraggedRightOffIsStranded() {
        XCTAssertTrue(Stranded.isStranded(frame(x: 1500, y: 300), on: [built]))
        XCTAssertTrue(Stranded.isStranded(frame(x: -190, y: 300), on: [built]))
        XCTAssertTrue(Stranded.isStranded(frame(x: 600, y: -250), on: [built]))
    }

    func testCompletelyOffIsStranded() {
        XCTAssertTrue(Stranded.isStranded(frame(x: 5_000, y: 5_000), on: [built]))
    }

    /// The case this exists for: a frame saved on a display that has since been
    /// unplugged points at coordinates nobody can see.
    func testAFrameOnAVanishedDisplayIsStranded() {
        let onSecond = frame(x: 2_600, y: 700)
        XCTAssertFalse(Stranded.isStranded(onSecond, on: [built, second]))
        XCTAssertTrue(Stranded.isStranded(onSecond, on: [built]),
                      "unplugging the display it was on left it reachable")
    }

    /// Each screen on its own. Split across two, it is visible on both, and
    /// adding the halves would call a genuinely awkward position fine.
    func testTheShareIsPerScreenNotTotal() {
        // Straddling the seam: half on each, so no single screen shows enough.
        let straddling = CGRect(x: 1512 - pet.width / 2, y: 300,
                                width: pet.width, height: pet.height)
        XCTAssertEqual(Stranded.visibleShare(straddling, on: [built, second]), 0.5,
                       accuracy: 0.01)
    }

    func testNoScreensAtAllStrandsNothing() {
        XCTAssertFalse(Stranded.isStranded(frame(x: 0, y: 0), on: []))
        XCTAssertNil(Stranded.home(for: frame(x: 0, y: 0), on: []))
        XCTAssertNil(Stranded.screen(for: frame(x: 0, y: 0), among: []))
    }

    func testAZeroSizedFrameIsNotStranded() {
        XCTAssertFalse(Stranded.isStranded(CGRect(x: 0, y: 0, width: 0, height: 0),
                                           on: [built]))
    }

    // MARK: - Where it goes back to

    func testItGoesToTheMiddleOfTheScreen() {
        let home = Stranded.home(for: frame(x: 5_000, y: 5_000), on: [built])
        XCTAssertEqual(home?.midX ?? 0, built.midX, accuracy: 1)
        XCTAssertEqual(home?.midY ?? 0, built.midY, accuracy: 1)
    }

    func testItKeepsItsOwnSize() {
        let home = Stranded.home(for: frame(x: 5_000, y: 5_000), on: [built])
        XCTAssertEqual(home?.size, pet)
    }

    /// It goes back to the screen it was mostly on, not always the first one.
    func testItReturnsToTheScreenItWasOn() {
        let mostlySecond = frame(x: 2_000, y: 700)
        let home = Stranded.home(for: mostlySecond, on: [built, second])
        XCTAssertEqual(home?.midX ?? 0, second.midX, accuracy: 1)
    }

    /// Overlapping nothing, it goes to whichever screen it was nearest, which
    /// is the closest thing to "where it was" that still exists.
    func testWithNoOverlapItTakesTheNearestScreen() {
        // Far off to the right of the second display.
        let away = frame(x: 6_000, y: 700)
        XCTAssertEqual(Stranded.screen(for: away, among: [built, second]), second)
        // And far off to the left of the built in one.
        let other = frame(x: -3_000, y: 300)
        XCTAssertEqual(Stranded.screen(for: other, among: [built, second]), built)
    }

    /// Whatever it decides, the answer has to be somewhere it is not stranded,
    /// or the recovery would run again on the next check for ever.
    func testComingHomeIsNeverStrandedAgain() {
        for start in [frame(x: 5_000, y: 5_000), frame(x: -900, y: -900),
                      frame(x: 1_500, y: 300), frame(x: 2_600, y: 700)] {
            for screens in [[built], [built, second]] {
                guard let home = Stranded.home(for: start, on: screens) else {
                    return XCTFail("no home on \(screens.count) screens")
                }
                XCTAssertFalse(Stranded.isStranded(home, on: screens),
                               "came home to somewhere still out of reach")
            }
        }
    }

    /// A pet larger than the screen cannot show `mustShow` of itself anywhere,
    /// and must not be dragged to the middle again on every single check.
    func testSomethingBiggerThanTheScreenSettles() {
        let huge = CGRect(x: 4_000, y: 4_000, width: 3_000, height: 2_000)
        guard let home = Stranded.home(for: huge, on: [built]) else {
            return XCTFail("no home")
        }
        XCTAssertEqual(home.midX, built.midX, accuracy: 1)
        XCTAssertEqual(Stranded.home(for: home, on: [built]), home,
                       "coming home moved it again")
    }
}
