import XCTest
@testable import SquawkCore

final class DayTimeTests: XCTestCase {
    func testParsesAndPrintsTheConfigForm() {
        let time = DayTime(text: "10:00")
        XCTAssertEqual(time, DayTime(hour: 10, minute: 0))
        XCTAssertEqual(DayTime(hour: 15).text, "15:00")
        XCTAssertEqual(DayTime(hour: 9, minute: 5).text, "09:05")
    }

    func testRefusesRubbish() {
        for bad in ["", "10", "25:00", "10:61", "ten:00", "10:00:00", "-1:00"] {
            XCTAssertNil(DayTime(text: bad), bad)
        }
    }

    func testOutOfRangeValuesAreClamped() {
        XCTAssertEqual(DayTime(hour: 99, minute: 99), DayTime(hour: 23, minute: 59))
    }
}

final class ConfigTests: XCTestCase {
    private func temporaryPath() -> String {
        NSTemporaryDirectory() + "squawk-config-\(UUID().uuidString)/config.json"
    }

    func testDefaultsAreTenAndThree() {
        XCTAssertEqual(SquawkConfig().checkTimes, [DayTime(hour: 10), DayTime(hour: 15)])
    }

    func testRoundTripsThroughDisk() {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        var config = SquawkConfig()
        config.checkForUpdates = true
        config.dialDiameter = 420
        config.updateCheckTimes = ["08:30", "20:15"]
        XCTAssertTrue(ConfigFile.save(config, path: path))
        XCTAssertEqual(ConfigFile.load(path: path), config)
    }

    /// A hand edited file should degrade, not reset everything it got right.
    func testUnparseableTimesAreDroppedNotFatal() {
        var config = SquawkConfig()
        config.updateCheckTimes = ["10:00", "not a time", "15:00", "99:99"]
        XCTAssertEqual(config.checkTimes, [DayTime(hour: 10), DayTime(hour: 15)])
    }

    func testDuplicateTimesCollapse() {
        var config = SquawkConfig()
        config.updateCheckTimes = ["10:00", "10:00", "15:00"]
        XCTAssertEqual(config.checkTimes.count, 2)
    }

    func testMissingFileGivesDefaults() {
        XCTAssertEqual(ConfigFile.load(path: "/nonexistent/squawk/config.json"), SquawkConfig())
    }

    /// It records what the dial looks like and whether it opens at login, so it
    /// is not world readable.
    func testTheFileIsPrivate() throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: (path as NSString).deletingLastPathComponent) }
        ConfigFile.save(SquawkConfig(), path: path)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, 0o600)
    }

    func testStoredSizeAndOpacityAreClampedOnRead() {
        var config = SquawkConfig()
        config.dialDiameter = 9_999
        config.dialOpacity = -3
        XCTAssertEqual(config.clampedDiameter, DialGeometry.range.upperBound)
        XCTAssertEqual(config.clampedOpacity, DialOpacity.range.lowerBound, accuracy: 0.001)
    }
}

final class ScheduledCheckTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 18) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 9, day: day, hour: hour, minute: minute
        ))!
    }

    private let times = [DayTime(hour: 10), DayTime(hour: 15)]

    func testNotDueBeforeTheFirstSlot() {
        XCTAssertFalse(UpdateSchedule.isDue(
            at: times, now: at(9, 30), lastCheck: at(8), calendar: calendar
        ))
    }

    func testDueOnceTheTenOClockSlotPasses() {
        XCTAssertTrue(UpdateSchedule.isDue(
            at: times, now: at(10, 1), lastCheck: at(8), calendar: calendar
        ))
    }

    /// Having checked at ten does not make three o'clock due early.
    func testCheckingAtTenDoesNotSatisfyThree() {
        XCTAssertFalse(UpdateSchedule.isDue(
            at: times, now: at(14), lastCheck: at(10, 5), calendar: calendar
        ))
        XCTAssertTrue(UpdateSchedule.isDue(
            at: times, now: at(15, 1), lastCheck: at(10, 5), calendar: calendar
        ))
    }

    /// Asleep through a slot means checking on waking, not skipping the day.
    func testASleptThroughSlotStillFires() {
        XCTAssertTrue(UpdateSchedule.isDue(
            at: times, now: at(23), lastCheck: at(9), calendar: calendar
        ))
    }

    /// Before the day's first slot, yesterday's last one is what counts.
    func testEarlyMorningLooksBackToYesterday() {
        XCTAssertTrue(UpdateSchedule.isDue(
            at: times, now: at(2, day: 18), lastCheck: at(9, day: 17), calendar: calendar
        ))
        XCTAssertFalse(UpdateSchedule.isDue(
            at: times, now: at(2, day: 18), lastCheck: at(16, day: 17), calendar: calendar
        ))
    }

    func testNeverCheckedIsDue() {
        XCTAssertTrue(UpdateSchedule.isDue(at: times, now: at(11), lastCheck: nil, calendar: calendar))
    }

    func testNoTimesMeansNeverDue() {
        XCTAssertFalse(UpdateSchedule.isDue(at: [], now: at(11), lastCheck: nil, calendar: calendar))
    }
}

