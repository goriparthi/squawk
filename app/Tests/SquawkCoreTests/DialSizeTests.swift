import XCTest
@testable import SquawkCore

final class DialSizeTests: XCTestCase {
    func testSizesAreOrdered() {
        XCTAssertLessThan(DialSize.small.diameter, DialSize.medium.diameter)
        XCTAssertLessThan(DialSize.medium.diameter, DialSize.large.diameter)
    }

    /// The card is centred inside the ring, so its corners must clear the inner
    /// edge of the band at every size or text would sit under the arcs.
    func testCardFitsInsideTheRingAtEverySize() {
        for size in DialSize.allCases {
            let innerRadius = size.diameter / 2 - size.ringBand
            // Generous card height; the real one is shorter than this.
            let halfDiagonal = (pow(size.cardWidth / 2, 2) + pow(60.0, 2)).squareRoot()
            XCTAssertLessThan(
                halfDiagonal, innerRadius,
                "\(size.rawValue): card corner escapes the ring"
            )
        }
    }

    func testProportionsHoldAcrossSizes() {
        for size in DialSize.allCases {
            let ratio = size.ringWidth / size.diameter
            XCTAssertEqual(ratio, 0.05, accuracy: 0.004, "\(size.rawValue) ring weight drifts")
        }
    }

    func testSmallStillLeavesAUsableCard() {
        XCTAssertGreaterThan(DialSize.small.cardWidth, 100)
    }

    func testUnknownOrMissingNameFallsBackToDefault() {
        XCTAssertEqual(DialSize.named(nil), .medium)
        XCTAssertEqual(DialSize.named("enormous"), .medium)
        XCTAssertEqual(DialSize.named("large"), .large)
    }

    func testCaptionNeverGoesBelowLegible() {
        for size in DialSize.allCases {
            XCTAssertGreaterThanOrEqual(size.captionFontSize, 10, size.rawValue)
        }
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
