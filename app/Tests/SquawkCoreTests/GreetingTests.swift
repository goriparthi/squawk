import XCTest
@testable import SquawkCore

final class GreetingTests: XCTestCase {
    /// The whole point: a pet with one catchphrase is a doorbell.
    func testItNeverRepeatsTheLastOne() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let previous = Greeting.anyTime.randomElement()
            let said = Greeting.next(after: previous, hour: 14, using: &generator)
            XCTAssertNotEqual(said, previous)
        }
    }

    func testTheHourChangesWhatItMightSay() {
        XCTAssertTrue(Greeting.pool(at: 23).contains(Greeting.late[0]))
        XCTAssertTrue(Greeting.pool(at: 1).contains(Greeting.late[0]))
        XCTAssertTrue(Greeting.pool(at: 5).contains(Greeting.early[0]))
        XCTAssertFalse(Greeting.pool(at: 14).contains(Greeting.late[0]))
        XCTAssertFalse(Greeting.pool(at: 14).contains(Greeting.early[0]))
    }

    /// Even asked for the only line it has, it answers with something.
    func testItAlwaysSaysSomething() {
        var generator = SystemRandomNumberGenerator()
        for hour in 0..<24 {
            XCTAssertFalse(Greeting.next(after: nil, hour: hour, using: &generator).isEmpty)
        }
    }

    func testEveryLineIsShortEnoughToSayOutLoud() {
        for line in Greeting.anyTime + Greeting.late + Greeting.early {
            XCTAssertLessThanOrEqual(line.count, 90, line)
            XCTAssertFalse(line.contains("—"), "no em dashes: \(line)")
        }
    }
}
