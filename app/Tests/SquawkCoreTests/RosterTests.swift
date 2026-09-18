import XCTest
@testable import SquawkCore

final class RosterTests: XCTestCase {
    private func request(_ id: String, session: String = "s1", wait: Double? = nil) -> PendingRequest {
        PendingRequest(
            id: id,
            sessionId: session,
            cwd: "/Users/x/proj",
            tool: "Bash",
            summary: "ls",
            waitSeconds: wait
        )
    }

    func testArrivalOrderIsPreserved() {
        var roster = Roster()
        roster.add(request("a"))
        roster.add(request("b"))
        XCTAssertEqual(roster.entries.map(\.id), ["a", "b"])
    }

    func testRepeatedIDReplacesRatherThanStacks() {
        var roster = Roster()
        XCTAssertTrue(roster.add(request("a")))
        XCTAssertFalse(roster.add(request("a")))
        XCTAssertEqual(roster.count, 1)
    }

    func testExpiryReturnsAndRemovesOnlyStaleEntries() {
        var roster = Roster()
        let start = Date(timeIntervalSince1970: 1_000)
        roster.add(request("old", wait: 30), now: start)
        roster.add(request("new", wait: 300), now: start)
        let expired = roster.expire(now: start.addingTimeInterval(60), fallback: 120)
        XCTAssertEqual(expired.map(\.id), ["old"])
        XCTAssertEqual(roster.entries.map(\.id), ["new"])
    }

    // Each arc dies with the hook that raised it. A shared lifetime let an arc
    // outlive its listener, so approving it sent a decision into a closed socket.
    func testEachEntryExpiresOnItsOwnDeclaredBudget() {
        var roster = Roster()
        let start = Date(timeIntervalSince1970: 1_000)
        roster.add(request("short", wait: 10), now: start)
        roster.add(request("long", wait: 600), now: start)
        XCTAssertEqual(roster.expire(now: start.addingTimeInterval(11), fallback: 120).map(\.id), ["short"])
        XCTAssertEqual(roster.count, 1)
    }

    func testMissingBudgetFallsBackForOlderHooks() {
        var roster = Roster()
        let start = Date(timeIntervalSince1970: 1_000)
        roster.add(request("legacy", wait: nil), now: start)
        XCTAssertTrue(roster.expire(now: start.addingTimeInterval(30), fallback: 120).isEmpty)
        XCTAssertEqual(roster.expire(now: start.addingTimeInterval(121), fallback: 120).map(\.id), ["legacy"])
    }

    func testSessionCountIsDistinct() {
        var roster = Roster()
        roster.add(request("a", session: "s1"))
        roster.add(request("b", session: "s1"))
        roster.add(request("c", session: "s2"))
        XCTAssertEqual(roster.count, 3)
        XCTAssertEqual(roster.sessionCount, 2)
    }

    func testProjectIsTheWorkingDirectoryLeaf() {
        XCTAssertEqual(request("a").project, "proj")
    }
}
