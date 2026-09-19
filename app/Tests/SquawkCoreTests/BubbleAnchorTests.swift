import XCTest
@testable import SquawkCore

final class BubbleAnchorTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1_440, height: 900)
    private let width: CGFloat = 296

    func testItDoesNotMoveInTheMiddle() {
        XCTAssertEqual(BubbleAnchor.shift(centre: 720, width: width, visible: screen), 0)
    }

    /// The whole bubble has to be on the display, whichever edge the pet is at.
    func testItSlidesInsideBothEdges() {
        for centre in stride(from: 0.0, through: 1_440.0, by: 10.0) {
            let shift = BubbleAnchor.shift(centre: CGFloat(centre), width: width,
                                           visible: screen)
            let left = CGFloat(centre) + shift - width / 2
            let right = CGFloat(centre) + shift + width / 2
            // Except where the pet itself is off the display, which is a
            // different problem and not one the bubble can solve by leaning.
            guard CGFloat(centre) > width / 2, CGFloat(centre) < 1_440 - width / 2 else { continue }
            XCTAssertGreaterThanOrEqual(left, screen.minX, "clipped left at \(centre)")
            XCTAssertLessThanOrEqual(right, screen.maxX, "clipped right at \(centre)")
        }
    }

    /// The guarantee: a pet with a little clearance from the edge gets its
    /// whole bubble on screen, and clear of the edge rather than touching it.
    func testAPetWithClearanceGetsItsWholeBubble() {
        let needed = BubbleAnchor.clearanceNeeded(width: width)
        for offset in stride(from: needed, through: 400, by: 7) {
            for centre in [screen.minX + offset, screen.maxX - offset] {
                let shift = BubbleAnchor.shift(centre: centre, width: width, visible: screen)
                XCTAssertGreaterThanOrEqual(centre + shift - width / 2,
                                            screen.minX + BubbleAnchor.margin - 0.5,
                                            "clipped left with centre at \(centre)")
                XCTAssertLessThanOrEqual(centre + shift + width / 2,
                                         screen.maxX - BubbleAnchor.margin + 0.5,
                                         "clipped right with centre at \(centre)")
            }
        }
    }

    /// A pet pushed right into the corner is itself half off the display, and
    /// the bubble leans as far as it can rather than tearing off its tail.
    func testInTheCornerItLeansAsFarAsItCan() {
        let shift = BubbleAnchor.shift(centre: screen.minX + 4, width: width, visible: screen)
        XCTAssertEqual(shift, width / 2 - BubbleAnchor.tailRoom, accuracy: 0.5)
    }

    /// A display that does not start at zero, which is every second monitor.
    func testItWorksOnADisplayWithAnOffset() {
        let second = CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        let centre = second.minX + BubbleAnchor.clearanceNeeded(width: width) + 40
        let shift = BubbleAnchor.shift(centre: centre, width: width, visible: second)
        XCTAssertGreaterThanOrEqual(centre + shift - width / 2,
                                    second.minX + BubbleAnchor.margin - 0.5)
    }

    /// Never so far that the tail leaves the bubble it is attached to.
    func testTheTailNeverRunsOffTheBubble() {
        for centre in [-500.0, 0.0, 1_440.0, 3_000.0] {
            let shift = BubbleAnchor.shift(centre: CGFloat(centre), width: width,
                                           visible: screen)
            XCTAssertLessThanOrEqual(abs(shift), width / 2 - BubbleAnchor.tailRoom)
        }
    }

    /// Over the pet by default; under it once the pet is against the top of
    /// the display, because the pet is the thing the person put where it is.
    func testItGoesUnderWhenThereIsNoRoomAbove() {
        let top: CGFloat = 900
        XCTAssertFalse(BubbleAnchor.shouldSitBelow(
            panelTop: 700, bubbleHeight: 184, visibleTop: top, currentlyBelow: false))
        XCTAssertTrue(BubbleAnchor.shouldSitBelow(
            panelTop: 920, bubbleHeight: 184, visibleTop: top, currentlyBelow: false),
            "the bubble's top is off the display")
    }

    /// Sticky, or dragging along the top edge flips it back and forth.
    func testItOnlyComesBackOverOnceThereIsRoom() {
        let top: CGFloat = 900
        // Just under the edge: over would be clipped, so it stays under.
        XCTAssertTrue(BubbleAnchor.shouldSitBelow(
            panelTop: 880, bubbleHeight: 184, visibleTop: top, currentlyBelow: true))
        // Well down the screen: the whole bubble fits again.
        XCTAssertFalse(BubbleAnchor.shouldSitBelow(
            panelTop: 600, bubbleHeight: 184, visibleTop: top, currentlyBelow: true))
    }
}
