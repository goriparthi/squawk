import XCTest
@testable import SquawkCore

final class ListeningTests: XCTestCase {
    func testItHearsItsNameAnywhereInTheRun() {
        let wake = Listening.wakeWords(persona: "Ember")
        XCTAssertEqual(Listening.afterWake("so anyway ember what's waiting", wakeWords: wake),
                       "what's waiting")
        XCTAssertNil(Listening.afterWake("what's waiting", wakeWords: wake))
    }

    /// The app's own name is also a project people work in, so a command that
    /// names this repo must not read as the wake word with nothing after it.
    func testItsOwnNameCanAlsoBeTheProjectBeingNamed() {
        let wake = Listening.wakeWords(persona: "Ember")
        XCTAssertEqual(Listening.afterWake("ember open squawk", wakeWords: wake), "open squawk")
        XCTAssertEqual(Listening.heard("open squawk"), .open("squawk"))
    }

    /// Said twice while correcting yourself, the command still lands, because
    /// the verb is looked for anywhere in what follows.
    func testSayingTheNameTwiceStillWorks() {
        let wake = Listening.wakeWords(persona: "Ember")
        XCTAssertEqual(Listening.afterWake("ember no ember status", wakeWords: wake),
                       "no ember status")
        XCTAssertEqual(Listening.heard("no ember status"), .status)
    }

    func testTheVerbsAreTheOnesPeopleSay() {
        XCTAssertEqual(Listening.heard("what's waiting"), .status)
        XCTAssertEqual(Listening.heard("anything for me"), .status)
        XCTAssertEqual(Listening.heard("approve squawk"), .approve("squawk"))
        XCTAssertEqual(Listening.heard("deny that one"), .deny("that one"))
        XCTAssertEqual(Listening.heard("open collect db"), .open("collect db"))
        XCTAssertEqual(Listening.heard("be quiet"), .quiet)
        XCTAssertEqual(Listening.heard("yes"), .yes)
        XCTAssertEqual(Listening.heard(""), .unknown)
        XCTAssertEqual(Listening.heard("the weather is nice"), .unknown)
    }

    /// "no, deny that" is a denial, not a no to some earlier question.
    func testAVerbOutranksBareAgreement() {
        XCTAssertEqual(Listening.heard("no deny that"), .deny("that"))
        XCTAssertEqual(Listening.heard("yes approve it"), .approve("it"))
    }

    /// Nobody says the underscore.
    func testProjectNamesAreMatchedAsSpoken() {
        let projects = ["collect_db", "squawk", "ballottrax"]
        XCTAssertEqual(Listening.match("collect db", against: projects), ["collect_db"])
        XCTAssertEqual(Listening.match("squawk", against: projects), ["squawk"])
        XCTAssertEqual(Listening.match("ballot", against: projects), ["ballottrax"])
        XCTAssertTrue(Listening.match("something else", against: projects).isEmpty)
    }
}

final class VoiceCommandTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private func target(_ id: String, _ project: String, risky: Bool = false,
                        decides: Bool = true) -> SpokenTarget {
        SpokenTarget(id: id, project: project, risky: risky, awaitsDecision: decides)
    }

    func testDenyingGoesStraightThrough() {
        let outcome = VoiceCommand.outcome(for: .deny("squawk"),
                                           targets: [target("a", "squawk", risky: true)], now: now)
        XCTAssertEqual(outcome, .decide(id: "a", allow: false))
    }

    /// The one that matters: approving something risky is asked again, out
    /// loud, and only a yes inside the window actually does it.
    func testApprovingSomethingRiskyIsConfirmedFirst() {
        let targets = [target("a", "squawk", risky: true)]
        let outcome = VoiceCommand.outcome(for: .approve("squawk"), targets: targets, now: now)
        guard case .confirm(_, let id, let allow) = outcome else {
            return XCTFail("expected a confirmation, got \(outcome)")
        }
        XCTAssertEqual(id, "a")
        XCTAssertTrue(allow)

        let pending = VoiceCommand.Pending(id: "a", allow: true, asked: now)
        XCTAssertEqual(VoiceCommand.outcome(for: .yes, targets: targets, pending: pending, now: now),
                       .decide(id: "a", allow: true))
    }

    /// A yes overheard a minute later decides nothing.
    func testAConfirmationLapses() {
        let targets = [target("a", "squawk", risky: true)]
        let pending = VoiceCommand.Pending(id: "a", allow: true, asked: now)
        let later = now.addingTimeInterval(VoiceCommand.confirmWindow + 1)
        XCTAssertEqual(VoiceCommand.outcome(for: .yes, targets: targets, pending: pending, now: later),
                       .ignored)
    }

    func testAPlainApprovalNeedsNoConfirmation() {
        XCTAssertEqual(
            VoiceCommand.outcome(for: .approve("squawk"), targets: [target("a", "squawk")], now: now),
            .decide(id: "a", allow: true))
    }

    /// Never a guess between two: being wrong runs something nobody asked for.
    func testItRefusesToChooseBetweenTwo() {
        let targets = [target("a", "squawk"), target("b", "collect_db")]
        guard case .say(let said) = VoiceCommand.outcome(for: .approve(""), targets: targets, now: now)
        else { return XCTFail("expected a question") }
        XCTAssertTrue(said.contains("Which one?"), said)
        XCTAssertTrue(said.contains("squawk") && said.contains("collect_db"), said)
    }

    /// With nothing named it acts on the one you are looking at.
    func testTheSelectedOneIsTheDefault() {
        let targets = [target("a", "squawk"), target("b", "collect_db")]
        XCTAssertEqual(
            VoiceCommand.outcome(for: .approve(""), targets: targets, selected: "b", now: now),
            .decide(id: "b", allow: true))
    }

    func testAnAttentionEntryCannotBeDecided() {
        let targets = [target("a", "squawk", decides: false)]
        guard case .say(let said) = VoiceCommand.outcome(for: .approve(""), targets: targets, now: now)
        else { return XCTFail("expected a refusal") }
        XCTAssertTrue(said.contains("Nothing is waiting on a decision"), said)
    }

    func testAStrayYesDoesNothing() {
        XCTAssertEqual(VoiceCommand.outcome(for: .yes, targets: [target("a", "squawk")], now: now),
                       .ignored)
        XCTAssertEqual(VoiceCommand.outcome(for: .unknown, targets: [], now: now), .ignored)
    }
}

final class SpokenCommandTests: XCTestCase {
    private let wake = Listening.wakeWords(persona: "Ember")

    private func command(_ transcript: String, final: Bool = true,
                         requiresWake: Bool = true) -> Intent? {
        Listening.command(from: transcript, final: final, wakeWords: wake,
                          requiresWake: requiresWake)
    }

    /// The bug this function exists to prevent: on a partial transcript
    /// "approve" would fire against whatever was selected, before the project
    /// being named had been heard at all.
    func testADecisionWaitsForTheEndOfTheSentence() {
        XCTAssertNil(command("ember approve", final: false))
        XCTAssertEqual(command("ember approve", final: true), .approve(""))
        XCTAssertNil(command("ember yes", final: false))
    }

    /// Looking things up is safe to do the moment it is understood.
    func testLookingActsOnAPartial() {
        XCTAssertEqual(command("ember what's waiting", final: false), .status)
        XCTAssertEqual(command("ember open squawk", final: false), .open("squawk"))
        XCTAssertEqual(command("ember be quiet", final: false), .quiet)
    }

    func testWithoutItsNameNothingHappens() {
        XCTAssertNil(command("approve squawk"))
        XCTAssertNil(command("ember"))
        XCTAssertNil(command("ember the weather is nice"))
    }

    /// Holding the key is already having said the name.
    func testHoldingTheKeyNeedsNoName() {
        XCTAssertEqual(command("approve squawk", requiresWake: false), .approve("squawk"))
        XCTAssertNil(command("approve squawk", final: false, requiresWake: false))
    }
}
