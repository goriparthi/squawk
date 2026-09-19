import XCTest
@testable import SquawkCore

final class AnswersTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Denver")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }
    private func at(_ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(timeZone: zone, year: 2026, month: 9, day: 19,
                                           hour: hour, minute: minute))!
    }

    /// The one a model gets confidently wrong every time, because it cannot
    /// know it. Nothing with a right answer on the machine is ever generated.
    func testTheClockIsComputedNotGuessed() {
        XCTAssertEqual(Answers.exact(for: "what time is it", now: at(16, 15),
                                     calendar: calendar, timeZone: zone),
                       "It's quarter past 4 in the afternoon.")
        XCTAssertEqual(Answers.exact(for: "what's the date", now: at(9, 0),
                                     calendar: calendar, timeZone: zone),
                       "It's September the 19th, 2026.")
        XCTAssertEqual(Answers.exact(for: "what day is it", now: at(9, 0),
                                     calendar: calendar, timeZone: zone),
                       "It's Saturday, September the 19th, 2026.")
    }

    func testAClockIsReadTheWayItIsSpoken() {
        XCTAssertEqual(Answers.spokenTime(at(12, 0), calendar: calendar), "12 o'clock in the afternoon")
        XCTAssertEqual(Answers.spokenTime(at(0, 30), calendar: calendar), "half past 12 in the morning")
        XCTAssertEqual(Answers.spokenTime(at(19, 45), calendar: calendar), "quarter to 8")
        XCTAssertEqual(Answers.spokenTime(at(8, 5), calendar: calendar), "8 oh 5 in the morning")
    }

    func testOrdinalsReadProperly() {
        XCTAssertEqual(Answers.ordinal("1"), "1st")
        XCTAssertEqual(Answers.ordinal("11"), "11th")
        XCTAssertEqual(Answers.ordinal("22"), "22nd")
        XCTAssertEqual(Answers.ordinal("13"), "13th")
    }

    func testAnythingElseIsNotAnsweredHere() {
        XCTAssertNil(Answers.exact(for: "who wrote dracula"))
        XCTAssertNil(Answers.exact(for: ""))
    }

    func testWeatherAndNoiseAreToldApart() {
        XCTAssertTrue(Answers.isAboutWeather("what's the weather like"))
        XCTAssertTrue(Answers.isAboutWeather("is it going to rain"))
        XCTAssertFalse(Answers.isAboutWeather("who wrote dracula"))
        // Two words near a pet is someone talking to someone else.
        XCTAssertFalse(Answers.isWorthAnswering("oh right"))
        XCTAssertTrue(Answers.isWorthAnswering("who wrote dracula"))
    }
}
