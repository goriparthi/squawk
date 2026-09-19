import XCTest
@testable import SquawkCore

final class PhrasingTests: XCTestCase {
    private func briefing(_ projects: [String]) -> Briefing {
        Briefing(items: projects.map {
            Briefing.Item(project: $0, tool: "Bash", summary: "git push", risky: false,
                          awaitsDecision: true, waited: 5)
        })
    }

    func testAGoodRephrasingIsKept() {
        let two = briefing(["squawk", "collect_db"])
        XCTAssertEqual(
            Phrasing.accept("Two waiting. squawk wants to run git push, and collect_db does too.", for: two),
            "Two waiting. squawk wants to run git push, and collect_db does too.")
    }

    /// The whole point: a model that quietly drops a project has told you
    /// something false about what your agents are doing.
    func testDroppingAProjectIsRefused() {
        XCTAssertNil(Phrasing.accept("Two waiting, both want to push.",
                                     for: briefing(["squawk", "collect_db"])))
    }

    /// A model that reads more nicely by dropping the warning is worse than
    /// the stiff sentence. One did exactly this in testing.
    func testLosingTheRiskWarningIsRefused() {
        var risky = briefing(["squawk"])
        risky = Briefing(items: risky.items.map {
            Briefing.Item(project: $0.project, tool: $0.tool, summary: $0.summary,
                          risky: true, awaitsDecision: true, waited: $0.waited)
        })
        XCTAssertNil(Phrasing.accept("One waiting. squawk is pushing with force.", for: risky))
        XCTAssertNotNil(Phrasing.accept("One waiting. squawk wants a risky push.", for: risky))
    }

    func testLosingTheCountIsRefused() {
        XCTAssertNil(Phrasing.accept("squawk and collect_db are waiting on you.",
                                     for: briefing(["squawk", "collect_db"])))
    }

    func testReasoningAndMarkdownAreRefused() {
        let one = briefing(["squawk"])
        XCTAssertNil(Phrasing.accept("<think>ok</think> One waiting in squawk.", for: one))
        XCTAssertNil(Phrasing.accept("**One** waiting in squawk.", for: one))
        XCTAssertNil(Phrasing.accept("One waiting in squawk. See http://x.y", for: one))
    }

    func testAnEssayIsRefused() {
        let one = briefing(["squawk"])
        XCTAssertNil(Phrasing.accept("One waiting in squawk. " + String(repeating: "a", count: 300), for: one))
    }

    /// Models answer in quotation marks constantly; that is a tidy up, not a
    /// reason to throw the sentence away.
    func testQuotesAndNewlinesAreTidiedRatherThanRefused() {
        XCTAssertEqual(
            Phrasing.accept("\"One waiting.\nsquawk wants git push.\"", for: briefing(["squawk"])),
            "One waiting. squawk wants git push.")
    }

    func testNothingWaitingIsAcceptedOnlyIfItSaysSo() {
        let empty = Briefing(items: [])
        XCTAssertNotNil(Phrasing.accept("Nothing waiting, all clear.", for: empty))
        XCTAssertNil(Phrasing.accept("You have some things to look at.", for: empty))
    }

    func testTheFactsNameEveryProjectItWillBeJudgedOn() {
        let facts = Phrasing.facts(briefing(["squawk", "collect_db"]))
        XCTAssertTrue(facts.contains("squawk"))
        XCTAssertTrue(facts.contains("collect_db"))
        XCTAssertTrue(facts.contains("2 waiting"))
    }
}
