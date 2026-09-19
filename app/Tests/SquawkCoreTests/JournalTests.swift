import XCTest
@testable import SquawkCore

final class JournalTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_758_300_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }
    private func entry(_ kind: Journal.Entry.Kind, _ project: String?, ago: TimeInterval,
                       _ text: String = "git push") -> Journal.Entry {
        Journal.Entry(at: now.addingTimeInterval(-ago), kind: kind, project: project, text: text)
    }

    /// A record of someone's desk is not something to keep indefinitely.
    func testItForgetsAnythingOlderThanAWeek() {
        var journal = Journal()
        journal.add(entry(.approved, "squawk", ago: Journal.keepFor + 60), now: now)
        journal.add(entry(.approved, "squawk", ago: 60), now: now)
        XCTAssertEqual(journal.entries.count, 1)
    }

    func testABusyWeekStillHasACeiling() {
        var journal = Journal(entries: (0..<(Journal.mostEntries + 500)).map {
            entry(.approved, "squawk", ago: TimeInterval($0))
        })
        journal.prune(now: now)
        XCTAssertEqual(journal.entries.count, Journal.mostEntries)
    }

    func testItCountsTheDayAndNamesTheProjects() {
        var journal = Journal()
        for _ in 0..<3 { journal.add(entry(.approved, "squawk", ago: 600), now: now) }
        journal.add(entry(.denied, "collect_db", ago: 300), now: now)
        let today = journal.today(now: now, calendar: calendar)
        XCTAssertTrue(today.contains("approved 3"), today)
        XCTAssertTrue(today.contains("denied 1"), today)
        XCTAssertTrue(today.contains("collect_db"), today)
    }

    func testAQuietDaySaysSo() {
        XCTAssertEqual(Journal().today(now: now, calendar: calendar),
                       "Nothing has been approved or denied today.")
    }

    /// Spoken aloud, so "an hour ago" rather than a timestamp.
    func testTimesAreSaidTheWayPeopleSayThem() {
        XCTAssertEqual(Journal.ago(from: now.addingTimeInterval(-30), to: now), "just now")
        XCTAssertEqual(Journal.ago(from: now.addingTimeInterval(-600), to: now), "10 minutes ago")
        XCTAssertEqual(Journal.ago(from: now.addingTimeInterval(-3600), to: now), "an hour ago")
        XCTAssertEqual(Journal.ago(from: now.addingTimeInterval(-86_400), to: now), "yesterday")
    }

    func testItSurvivesBeingWrittenDown() throws {
        var journal = Journal()
        journal.add(entry(.approved, "squawk", ago: 10), now: now)
        let data = try JSONEncoder().encode(journal)
        XCTAssertEqual(try JSONDecoder().decode(Journal.self, from: data), journal)
    }
}

final class SituationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_758_300_000)
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Denver")!
        return calendar
    }

    /// The thing no other assistant can say: what your agents are doing.
    func testItSaysWhatIsWaiting() {
        let briefing = Briefing(items: [
            Briefing.Item(project: "squawk", tool: "Bash", summary: "git push --force",
                          risky: true, awaitsDecision: true, waited: 30),
        ])
        let lines = Situation.lines(
            Situation.State(now: now, place: "Denver", briefing: briefing),
            calendar: calendar, timeZone: TimeZone(identifier: "America/Denver")!)
        XCTAssertTrue(lines.contains { $0.contains("Denver") })
        XCTAssertTrue(lines.contains { $0.contains("squawk wants Bash, risky") })
    }

    func testAQuietDeskSaysSo() {
        let lines = Situation.lines(Situation.State(now: now),
                                    calendar: calendar, timeZone: .current)
        XCTAssertTrue(lines.contains { $0.contains("None of their agents is waiting") })
    }

    /// Small on purpose: a local model handed two pages of situation answers
    /// the situation rather than the question.
    /// Counts alone make a model guess which project something happened in,
    /// and it guesses wrong. The entries themselves are in the grounding.
    func testTheSituationNamesWhatActuallyHappened() {
        var journal = Journal()
        journal.add(Journal.Entry(at: now.addingTimeInterval(-600), kind: .denied,
                                  project: "collect_db", text: "drop table orders"), now: now)
        let summary = Situation.summary(Situation.State(now: now, journal: journal),
                                        calendar: calendar, timeZone: .current)
        XCTAssertTrue(summary.contains("denied in collect_db"), summary)
        XCTAssertTrue(summary.contains("drop table orders"), summary)
    }

    func testTheSummaryStaysShort() {
        var journal = Journal()
        for index in 0..<50 {
            journal.add(Journal.Entry(at: now.addingTimeInterval(-Double(index) * 60),
                                      kind: .approved, project: "p\(index)", text: "x"), now: now)
        }
        let briefing = Briefing(items: (0..<10).map {
            Briefing.Item(project: "project\($0)", tool: "Bash", summary: "something",
                          risky: false, awaitsDecision: true, waited: 1)
        })
        let summary = Situation.summary(
            Situation.State(now: now, place: "Denver", briefing: briefing, journal: journal,
                            atDeskFor: 4 * 3600, playing: true),
            calendar: calendar, timeZone: .current)
        XCTAssertLessThan(summary.count, 700, summary)
    }
}
