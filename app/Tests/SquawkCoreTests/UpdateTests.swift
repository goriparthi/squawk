import XCTest
@testable import SquawkCore

final class VersionTests: XCTestCase {
    // A string comparison gets this wrong, which is how an update stops being
    // offered the moment a minor version reaches double digits.
    func testDoubleDigitSegmentsBeatSingleDigits() {
        XCTAssertTrue(Version.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertFalse(Version.isNewer("0.9.0", than: "0.10.0"))
    }

    func testLeadingVIsIgnored() {
        XCTAssertTrue(Version.isNewer("v1.2.0", than: "1.1.9"))
        XCTAssertEqual(Version.order("v1.0.0", "1.0.0"), .orderedSame)
    }

    func testMissingSegmentsCountAsZero() {
        XCTAssertEqual(Version.order("1.2", "1.2.0"), .orderedSame)
        XCTAssertTrue(Version.isNewer("1.2.1", than: "1.2"))
    }

    func testSuffixesDoNotChangeOrdering() {
        XCTAssertEqual(Version.order("1.2.0-beta1", "1.2.0"), .orderedSame)
        XCTAssertTrue(Version.isNewer("1.3.0-rc1", than: "1.2.0"))
    }

    func testSameVersionIsNotNewer() {
        XCTAssertFalse(Version.isNewer("1.0.0", than: "1.0.0"))
    }
}

final class UpdateScheduleTests: XCTestCase {
    func testNeverCheckedIsDue() {
        XCTAssertTrue(UpdateSchedule.isDue(every: 24, lastCheck: nil))
    }

    func testNotDueBeforeTheIntervalElapses() {
        let now = Date()
        XCTAssertFalse(UpdateSchedule.isDue(
            every: 24, now: now, lastCheck: now.addingTimeInterval(-23 * 3600)
        ))
    }

    func testDueAfterTheIntervalElapses() {
        let now = Date()
        XCTAssertTrue(UpdateSchedule.isDue(
            every: 24, now: now, lastCheck: now.addingTimeInterval(-25 * 3600)
        ))
    }

    /// Zero hours turns the schedule off, which is what an unticked menu item means.
    func testZeroHoursNeverFires() {
        XCTAssertFalse(UpdateSchedule.isDue(every: 0, lastCheck: nil))
        XCTAssertFalse(UpdateSchedule.isDue(every: -1, lastCheck: nil))
    }

    func testStampRoundTripsThroughDisk() throws {
        let path = NSTemporaryDirectory() + "squawk-stamp-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        UpdateSchedule.recordCheck(at: when, path: path)
        let read = try XCTUnwrap(UpdateSchedule.lastCheck(path: path))
        XCTAssertEqual(read.timeIntervalSince1970, when.timeIntervalSince1970, accuracy: 0.001)
    }

    func testMissingStampReadsAsNever() {
        XCTAssertNil(UpdateSchedule.lastCheck(path: "/nonexistent/squawk/stamp"))
    }
}
