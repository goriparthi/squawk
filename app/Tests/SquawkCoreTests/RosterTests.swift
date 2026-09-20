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

/// Several agents at once: one cluster each on the ring, and answering one
/// keeps you in that session rather than throwing you to another project.
final class RosterGroupingTests: XCTestCase {
    private func request(_ id: String, session: String, cwd: String) -> PendingRequest {
        PendingRequest(id: id, sessionId: session, cwd: cwd, tool: "Bash", summary: "swift build")
    }

    private func make(_ interleaved: [(String, String)]) -> Roster {
        var roster = Roster()
        for (id, session) in interleaved {
            roster.add(request(id, session: session, cwd: "/Users/x/\(session)"))
        }
        return roster
    }

    /// Three agents interleaving put three projects' arcs around the ring in
    /// whatever order their calls landed, so nothing read as one agent wanting
    /// three things.
    func testOneAgentsCallsAreOneRun() {
        let roster = make([("a1", "a"), ("b1", "b"), ("a2", "a"), ("c1", "c"), ("b2", "b")])
        XCTAssertEqual(roster.grouped.map(\.id), ["a1", "a2", "b1", "b2", "c1"])
    }

    /// Sessions in the order they first spoke, so the ring does not reshuffle
    /// itself every time a second call arrives.
    func testSessionsKeepTheirArrivalOrder() {
        let roster = make([("b1", "b"), ("a1", "a"), ("b2", "b")])
        XCTAssertEqual(roster.grouped.map(\.id), ["b1", "b2", "a1"])
    }

    func testGroupingKeepsEveryEntryExactlyOnce() {
        let roster = make([("a1", "a"), ("b1", "b"), ("a2", "a"), ("c1", "c")])
        XCTAssertEqual(Set(roster.grouped.map(\.id)), Set(roster.entries.map(\.id)))
        XCTAssertEqual(roster.grouped.count, roster.entries.count)
    }

    func testABreakIsMarkedWhereEachSessionStarts() {
        let roster = make([("a1", "a"), ("b1", "b"), ("a2", "a"), ("c1", "c")])
        // grouped is a1, a2, b1, c1
        XCTAssertEqual(roster.sessionBreaks, [0, 2, 3])
    }

    func testOneSessionHasOneBreak() {
        XCTAssertEqual(make([("a1", "a"), ("a2", "a")]).sessionBreaks, [0])
        XCTAssertEqual(Roster().sessionBreaks, [])
    }

    // MARK: - Where you land after answering

    /// The half of the loop that costs you is the context switch, not the click.
    func testAnsweringStaysWithTheSameAgent() {
        let roster = make([("a1", "a"), ("b1", "b"), ("a2", "a")])
        XCTAssertEqual(roster.next(after: "a1"), "a2")
    }

    func testFinishingASessionMovesToTheNextOne() {
        let roster = make([("a1", "a"), ("b1", "b"), ("c1", "c")])
        XCTAssertEqual(roster.next(after: "a1"), "b1")
    }

    func testAnsweringTheLastThingLeavesNothingSelected() {
        XCTAssertNil(make([("a1", "a")]).next(after: "a1"))
    }

    /// Asked after the entry has already gone, which is the shape of the bug
    /// this had: `finish` removed the entry and then asked what came next.
    func testAnUnknownIdFallsBackRatherThanReturningNothing() {
        let roster = make([("a1", "a"), ("b1", "b")])
        XCTAssertEqual(roster.next(after: "gone"), "a1")
    }

    func testTheCardCanSayHowManyOtherAgentsAreWaiting() {
        let roster = make([("a1", "a"), ("a2", "a"), ("b1", "b"), ("c1", "c")])
        XCTAssertEqual(roster.otherSessions(than: "a1"), 2)
        XCTAssertEqual(roster.otherSessions(than: "b1"), 2)
        XCTAssertEqual(make([("a1", "a")]).otherSessions(than: "a1"), 0)
    }
}

/// Stepping through the stack by hand, and the geometry behind the front card.
final class CardStackTests: XCTestCase {
    private func make(_ ids: [(String, String)]) -> Roster {
        var roster = Roster()
        for (id, session) in ids {
            roster.add(PendingRequest(id: id, sessionId: session, cwd: "/Users/x/\(session)",
                                      tool: "Bash", summary: "swift build"))
        }
        return roster
    }

    /// A loop, not a list with an end: there is nothing useful at either end,
    /// and stopping dead reads as the gesture having failed.
    func testSteppingWraps() {
        let roster = make([("a1", "a"), ("a2", "a"), ("b1", "b")])
        XCTAssertEqual(roster.after("a1"), "a2")
        XCTAssertEqual(roster.after("b1"), "a1")
        XCTAssertEqual(roster.before("a1"), "b1")
        XCTAssertEqual(roster.before("a2"), "a1")
    }

    /// It steps through the grouped order, so one agent's calls are adjacent
    /// in the stack rather than interleaved with somebody else's.
    func testSteppingFollowsTheGrouping() {
        let roster = make([("a1", "a"), ("b1", "b"), ("a2", "a")])
        XCTAssertEqual(roster.after("a1"), "a2")
        XCTAssertEqual(roster.after("a2"), "b1")
    }

    func testOneEntryStepsToItself() {
        let roster = make([("a1", "a")])
        XCTAssertEqual(roster.after("a1"), "a1")
        XCTAssertEqual(roster.before("a1"), "a1")
    }

    func testAnEmptyRosterStepsNowhere() {
        XCTAssertNil(Roster().after("a1"))
        XCTAssertNil(Roster().before("a1"))
        XCTAssertNil(Roster().place(of: "a1"))
    }

    /// Selection can lag a removal by a frame, so an unknown id has to land
    /// somewhere rather than leaving nothing selected.
    func testAnUnknownIdLandsSomewhere() {
        let roster = make([("a1", "a"), ("b1", "b")])
        XCTAssertEqual(roster.after("gone"), "a1")
        XCTAssertEqual(roster.before("gone"), "b1")
    }

    func testPlaceCountsFromTheGroupedOrder() {
        let roster = make([("a1", "a"), ("b1", "b"), ("a2", "a")])
        XCTAssertEqual(roster.place(of: "a2")?.index, 1)
        XCTAssertEqual(roster.place(of: "b1")?.index, 2)
        XCTAssertEqual(roster.place(of: "a1")?.total, 3)
    }

    // MARK: - What is drawn behind the front card

    func testOneWaitingHasNoStack() {
        XCTAssertEqual(CardStack.depth(waiting: 1), 0)
        XCTAssertEqual(CardStack.headroom(waiting: 1), 0)
        XCTAssertEqual(CardStack.depth(waiting: 0), 0)
    }

    func testTheStackGrowsAndThenStops() {
        XCTAssertEqual(CardStack.depth(waiting: 2), 1)
        XCTAssertEqual(CardStack.depth(waiting: 3), 2)
        // Past two the strips are thinner than the gaps and it reads as texture.
        XCTAssertEqual(CardStack.depth(waiting: 9), CardStack.drawnDepth)
        XCTAssertEqual(CardStack.headroom(waiting: 9),
                       CGFloat(CardStack.drawnDepth) * CardStack.step)
    }

    func testEachOneSitsFurtherBackAndNarrower() {
        XCTAssertLessThan(CardStack.offset(behind: 0), CardStack.offset(behind: 1))
        XCTAssertLessThan(CardStack.inset(behind: 0), CardStack.inset(behind: 1))
        XCTAssertGreaterThan(CardStack.alpha(behind: 0), CardStack.alpha(behind: 1))
    }

    /// A card you cannot see is a card that is not saying anything is behind.
    func testNothingFadesToInvisible() {
        for index in 0..<10 {
            XCTAssertGreaterThanOrEqual(CardStack.alpha(behind: index), 0.15)
            XCTAssertLessThanOrEqual(CardStack.alpha(behind: index), 1)
        }
    }
}
