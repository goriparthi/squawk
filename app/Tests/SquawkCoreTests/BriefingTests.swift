import XCTest
@testable import SquawkCore

final class BriefingTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func request(_ id: String, project: String, tool: String = "Bash",
                         summary: String = "ls", decides: Bool = true) -> PendingRequest {
        PendingRequest(id: id, sessionId: "s-\(id)", cwd: "/Users/me/\(project)",
                       tool: tool, summary: summary, needsDecision: decides)
    }

    private func roster(_ entries: [(PendingRequest, TimeInterval)]) -> Roster {
        var roster = Roster()
        for (request, age) in entries {
            _ = roster.add(request, now: now.addingTimeInterval(-age))
        }
        return roster
    }

    func testNothingWaitingSaysSo() {
        XCTAssertEqual(Utterance.spoken(Briefing.of(Roster(), now: now)), "Nothing waiting.")
    }

    /// The one that has been sitting there longest is the one worth naming.
    func testTheLongestWaitIsNamedFirst() {
        let briefing = Briefing.of(roster([
            (request("a", project: "squawk"), 5),
            (request("b", project: "collect_db"), 90),
        ]), now: now)
        XCTAssertEqual(briefing.items.first?.project, "collect_db")
        XCTAssertEqual(briefing.waiting, 2)
        XCTAssertEqual(briefing.decisions, 2)
    }

    /// Attention entries are not decisions, and saying they are would send you
    /// looking for a button that is not there.
    func testAnAgentThatOnlyWantsYouIsNotADecision() {
        let briefing = Briefing.of(roster([
            (request("a", project: "squawk"), 10),
            (request("b", project: "ballot", tool: "idle_prompt", decides: false), 20),
        ]), now: now)
        XCTAssertEqual(briefing.decisions, 1)
        XCTAssertEqual(briefing.attention, 1)
        let spoken = Utterance.spoken(briefing)
        XCTAssertTrue(spoken.contains("ballot wants you."), spoken)
        XCTAssertTrue(spoken.contains("one needing a decision"), spoken)
    }

    func testRiskIsSaidOutLoud() {
        let briefing = Briefing.of(roster([
            (request("a", project: "squawk", summary: "git push --force"), 1),
        ]), now: now)
        XCTAssertEqual(briefing.risky, 1)
        XCTAssertTrue(Utterance.spoken(briefing).contains("risky"))
    }

    /// A spoken list of four is a queue nobody can hold in their head.
    func testItStopsNamingAndStartsCounting() {
        let briefing = Briefing.of(roster((1...5).map {
            (request("\($0)", project: "p\($0)"), TimeInterval(60 - $0))
        }), now: now)
        let spoken = Utterance.spoken(briefing)
        XCTAssertTrue(spoken.hasPrefix("Five waiting."), spoken)
        XCTAssertTrue(spoken.hasSuffix("And three more."), spoken)
    }

    func testSmallNumbersAreWordsAndLongCommandsAreCut() {
        XCTAssertEqual(Utterance.count(3), "three")
        XCTAssertEqual(Utterance.count(42), "42")
        XCTAssertLessThanOrEqual(Utterance.trimmed(String(repeating: "x", count: 400)).count, 61)
    }
}
