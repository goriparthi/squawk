import XCTest
@testable import SquawkCore

final class BehaviourRulesTests: XCTestCase {
    func testAnEmptyFileMeansTheBuiltInWording() {
        let rules = BehaviourRules.parse("")
        XCTAssertEqual(rules.instruction(for: .phrasing, fallback: "built in"), "built in")
        XCTAssertEqual(rules.instruction(for: .answering, fallback: "built in"), "built in")
    }

    func testASectionReplacesTheBuiltInWording() {
        let rules = BehaviourRules.parse("""
        # phrasing
        Be terse.

        # answering
        Be warm.
        """)
        XCTAssertEqual(rules.instruction(for: .phrasing, fallback: "built in"), "Be terse.")
        XCTAssertEqual(rules.instruction(for: .answering, fallback: "built in"), "Be warm.")
    }

    func testOnlyTheSectionsGivenAreReplaced() {
        let rules = BehaviourRules.parse("# phrasing\nBe terse.")
        XCTAssertEqual(rules.instruction(for: .phrasing, fallback: "built in"), "Be terse.")
        XCTAssertEqual(rules.instruction(for: .answering, fallback: "built in"), "built in")
    }

    /// Someone's scratch file, so half of it working beats all of it being
    /// thrown away because one heading was misspelled.
    func testAnUnknownHeadingIsIgnoredRatherThanFatal() {
        let rules = BehaviourRules.parse("""
        # Squawk behaviour
        Notes to myself that are not instructions.

        # phrasing
        Be terse.
        """)
        XCTAssertEqual(rules.instruction(for: .phrasing, fallback: "built in"), "Be terse.")
    }

    /// An unknown heading has to close the section above it, or its body is
    /// silently appended to whatever came before.
    func testAnUnknownHeadingDoesNotLeakIntoTheSectionAboveIt() {
        let rules = BehaviourRules.parse("""
        # phrasing
        Be terse.

        # notes
        Remember to buy milk.
        """)
        let wording = rules.instruction(for: .phrasing, fallback: "built in")
        XCTAssertEqual(wording, "Be terse.")
        XCTAssertFalse(wording.contains("milk"))
    }

    func testHeadingsAreMatchedLooselyEnoughToBeTyped() {
        for heading in ["# phrasing", "## Phrasing", "#   PHRASING  ", "### phrasing"] {
            let rules = BehaviourRules.parse("\(heading)\nBe terse.")
            XCTAssertEqual(rules.instruction(for: .phrasing, fallback: "built in"), "Be terse.",
                           "\(heading) was not read")
        }
    }

    func testAHeadingWithNothingUnderItKeepsTheBuiltInWording() {
        let rules = BehaviourRules.parse("# phrasing\n\n   \n")
        XCTAssertEqual(rules.instruction(for: .phrasing, fallback: "built in"), "built in")
    }

    /// A small model given two pages answers the pages. The file cannot crowd
    /// out the facts however much is pasted into it.
    func testAHugeSectionIsCut() {
        let rules = BehaviourRules.parse("# phrasing\n" + String(repeating: "a", count: 9_000))
        let wording = rules.instruction(for: .phrasing, fallback: "built in")
        XCTAssertEqual(wording.count, BehaviourRules.longest)
    }

    func testBodyTextKeepsItsOwnLineBreaks() {
        let rules = BehaviourRules.parse("# phrasing\nOne.\nTwo.")
        XCTAssertEqual(rules.instruction(for: .phrasing, fallback: ""), "One.\nTwo.")
    }

    /// The template is what someone edits first, so it has to parse back into
    /// exactly the wording it was built from.
    func testTheTemplateRoundTrips() {
        let text = BehaviourRules.template(phrasing: "Be terse.", answering: "Be warm.")
        let rules = BehaviourRules.parse(text)
        XCTAssertEqual(rules.instruction(for: .phrasing, fallback: "built in"), "Be terse.")
        XCTAssertEqual(rules.instruction(for: .answering, fallback: "built in"), "Be warm.")
    }

    func testAMissingFileIsNotAFailure() {
        let rules = BehaviourRules.load(path: NSTemporaryDirectory() + "/absent-\(UUID()).md")
        XCTAssertEqual(rules.instruction(for: .phrasing, fallback: "built in"), "built in")
    }

    func testItLivesBesideTheOtherSquawkFiles() {
        XCTAssertTrue(BehaviourRules.path(home: "/Users/x").hasPrefix("/Users/x/.squawk/"))
        XCTAssertTrue(BehaviourRules.path(home: "/Users/x").hasSuffix(".md"))
    }

    /// It rewords instructions Squawk was already sending. It cannot add a
    /// section, so it can never reach anything the app did not offer it.
    func testOnlyTheKnownSectionsExist() {
        XCTAssertEqual(Set(BehaviourRules.Section.allCases.map(\.rawValue)),
                       ["phrasing", "answering"])
    }
}
