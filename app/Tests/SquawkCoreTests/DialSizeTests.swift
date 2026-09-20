import XCTest
@testable import SquawkCore

final class DialSizeTests: XCTestCase {
    func testSizesAreOrdered() {
        XCTAssertLessThan(DialSize.small.diameter, DialSize.medium.diameter)
        XCTAssertLessThan(DialSize.medium.diameter, DialSize.large.diameter)
    }

    func testUnknownOrMissingNameFallsBackToDefault() {
        XCTAssertEqual(DialSize.named(nil), .medium)
        XCTAssertEqual(DialSize.named("enormous"), .medium)
        XCTAssertEqual(DialSize.named("large"), .large)
    }
}

final class DialOpacityTests: XCTestCase {
    func testStaysInsideTheRange() {
        XCTAssertEqual(DialOpacity.clamp(0.6), 0.6, accuracy: 0.0001)
        XCTAssertEqual(DialOpacity.clamp(2.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(DialOpacity.clamp(-5), DialOpacity.range.lowerBound, accuracy: 0.0001)
    }

    /// A fully transparent dial would be invisible but still on top, taking
    /// clicks nobody could aim, so zero is not reachable.
    func testNeverFullyTransparent() {
        XCTAssertGreaterThan(DialOpacity.clamp(0), 0)
        XCTAssertGreaterThan(DialOpacity.range.lowerBound, 0)
    }

    func testRubbishFallsBackToSolid() {
        XCTAssertEqual(DialOpacity.clamp(.nan), DialOpacity.default, accuracy: 0.0001)
        XCTAssertEqual(DialOpacity.clamp(.infinity), 1.0, accuracy: 0.0001)
    }
}

final class DialGeometryTests: XCTestCase {
    func testClampKeepsTheSliderHonest() {
        XCTAssertEqual(DialGeometry.clamp(10), DialGeometry.range.lowerBound)
        XCTAssertEqual(DialGeometry.clamp(9_999), DialGeometry.range.upperBound)
        XCTAssertEqual(DialGeometry.clamp(.nan), DialSize.default.diameter)
        XCTAssertEqual(DialGeometry.clamp(300.4), 300)
    }

    func testPresetsSitInsideTheSliderRange() {
        for size in DialSize.allCases {
            XCTAssertTrue(DialGeometry.range.contains(size.diameter), size.rawValue)
        }
    }

    func testNearestPresetTracksTheSlider() {
        XCTAssertEqual(DialSize.nearest(to: 150), .small)
        XCTAssertEqual(DialSize.nearest(to: 358), .medium)
        XCTAssertEqual(DialSize.nearest(to: 480), .large)
    }
}

final class PetSizeRangeTests: XCTestCase {
    /// The card is in the bubble, so the head can go right down to the floor of
    /// the range. There used to be a second, higher floor for the style that
    /// kept the card inside its own ring, and 150 was where it sat.
    func testTheHeadCanGoSmallNowTheCardIsNotInIt() {
        XCTAssertEqual(DialGeometry.range.lowerBound, 50)
        XCTAssertEqual(DialGeometry.clamp(50), 50)
        XCTAssertEqual(DialGeometry.clamp(60), 60)
    }

    func testTheSliderReachesBothEnds() {
        XCTAssertEqual(DialGeometry.clamp(DialGeometry.range.lowerBound),
                       DialGeometry.range.lowerBound)
        XCTAssertEqual(DialGeometry.clamp(DialGeometry.range.upperBound),
                       DialGeometry.range.upperBound)
    }
}

/// The bubble is its own surface, so what it holds is not sized by the pet.
/// Before this, "Open pane" and "Dismiss" were clipped to "Pa..." and "Cl..."
/// because the card was still the head's inscribed square.
final class SpeechBubbleSizeTests: XCTestCase {
    /// However small the pet is, the card it speaks from is the same width.
    func testTheCardDoesNotShrinkWithTheHead() {
        for head in DialGeometry.range.stride(by: 50) {
            XCTAssertEqual(DialGeometry.bubbleWidth(),
                           DialGeometry.bubbleCardWidth + 2 * DialGeometry.bubblePadding,
                           "head \(head) squeezed the bubble")
        }
    }

    func testTheWindowHoldsTheBubbleAtEverySize() {
        for head in DialGeometry.range.stride(by: 50) {
            let canvas = BodyGeometry.canvas(head: head)
            XCTAssertGreaterThanOrEqual(canvas.width, DialGeometry.bubbleWidth(),
                                        "the bubble overhangs the window at \(head)")
            XCTAssertGreaterThanOrEqual(BodyGeometry.bubbleHeight(head: head),
                                        DialGeometry.bubbleFloor)
        }
    }
}

private extension ClosedRange where Bound == CGFloat {
    func stride(by step: CGFloat) -> [CGFloat] {
        Swift.stride(from: lowerBound, through: upperBound, by: step).map { $0 }
    }
}
