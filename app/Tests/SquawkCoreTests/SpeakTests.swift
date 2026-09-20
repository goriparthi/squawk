import XCTest
@testable import SquawkCore

final class SpeakTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - The frame on the wire

    func testASpeakFrameIsReadBackAsOne() throws {
        let ask = SpeakRequest(text: "the migration is running", cwd: "/tmp/collect_db")
        let data = try WireCodec.encode(ask)
        guard case .speak(let decoded) = try WireCodec.frame(from: data) else {
            return XCTFail("a speak frame read back as something else")
        }
        XCTAssertEqual(decoded.text, "the migration is running")
        XCTAssertEqual(decoded.project, "collect_db")
    }

    /// A decision carries no `kind` at all, so the absence is what identifies
    /// it, and a hook from an older build still reads as one.
    func testADecisionFrameIsStillADecision() throws {
        let request = PendingRequest(
            id: "a", sessionId: "s", cwd: "/tmp/squawk", tool: "Bash", summary: "rm -rf build"
        )
        let data = try WireCodec.encode(request)
        guard case .decision(let decoded) = try WireCodec.frame(from: data) else {
            return XCTFail("a decision frame read back as something else")
        }
        XCTAssertEqual(decoded.id, "a")
    }

    func testAProjectlessLineHasNoProject() {
        XCTAssertNil(SpeakRequest(text: "hello", cwd: nil).project)
        XCTAssertNil(SpeakRequest(text: "hello", cwd: "").project)
    }

    // MARK: - The gate

    func testAnOrdinaryLineIsAdmitted() {
        var gate = SpeakGate()
        XCTAssertEqual(gate.admit("the tests are green", at: start),
                       .say("the tests are green"))
    }

    func testNothingToSayIsRefused() {
        var gate = SpeakGate()
        guard case .refused = gate.admit("   \n ", at: start) else {
            return XCTFail("whitespace was admitted")
        }
    }

    /// The pet sits on screen during screen shares, so a token read out loud
    /// is a token published. This is the whole reason the gate redacts.
    func testASecretIsMaskedBeforeItIsEverSaid() {
        var gate = SpeakGate()
        guard case .say(let line) = gate.admit(
            "deploying with --token ghp_abcdefghijklmnopqrstuvwxyz0123", at: start
        ) else { return XCTFail("refused a line that should have been said") }
        XCTAssertFalse(line.contains("ghp_abcdefghijklmnopqrstuvwxyz0123"))
        XCTAssertTrue(line.contains("••••"))
    }

    /// An escape sequence in a spoken line is exactly how you would hide what
    /// the pet is showing on screen while it says something else.
    func testControlCharactersAreFlattened() {
        var gate = SpeakGate()
        guard case .say(let line) = gate.admit("done\u{1B}[2Kand gone", at: start) else {
            return XCTFail("refused")
        }
        XCTAssertFalse(line.contains("\u{1B}"))
    }

    func testALongLineIsCutToWhatTheBubbleHolds() {
        var gate = SpeakGate()
        guard case .say(let line) = gate.admit(
            String(repeating: "a", count: SpeakGate.longest * 3), at: start
        ) else { return XCTFail("refused") }
        XCTAssertEqual(line.count, SpeakGate.longest)
    }

    func testASecondLineTooSoonIsRefused() {
        var gate = SpeakGate()
        _ = gate.admit("first", at: start)
        guard case .refused = gate.admit("second", at: start.addingTimeInterval(0.5)) else {
            return XCTFail("a line landed on top of the one still being said")
        }
    }

    func testALineAfterTheGapIsAdmitted() {
        var gate = SpeakGate()
        _ = gate.admit("first", at: start)
        guard case .say = gate.admit(
            "second", at: start.addingTimeInterval(SpeakGate.leastGap + 0.1)
        ) else { return XCTFail("refused a line that had waited its turn") }
    }

    /// A loop must not be able to hold the pet's mouth open, which is the
    /// failure a prompt injection would aim for.
    func testTheMinuteIsCapped() {
        var gate = SpeakGate()
        var at = start
        for index in 0..<SpeakGate.mostPerMinute {
            guard case .say = gate.admit("line \(index)", at: at) else {
                return XCTFail("refused line \(index), inside the cap")
            }
            at = at.addingTimeInterval(SpeakGate.leastGap)
        }
        guard case .refused = gate.admit("one too many", at: at) else {
            return XCTFail("the cap did not hold")
        }
    }

    func testTheCapIsRollingRatherThanFixed() {
        var gate = SpeakGate()
        var at = start
        for index in 0..<SpeakGate.mostPerMinute {
            _ = gate.admit("line \(index)", at: at)
            at = at.addingTimeInterval(SpeakGate.leastGap)
        }
        // A minute after the first, the window has moved off it.
        guard case .say = gate.admit("later", at: start.addingTimeInterval(61)) else {
            return XCTFail("the window never reopened")
        }
    }

    // MARK: - Where it sits among everything else the pet says

    /// An agent may not talk over a refusal or a wellness prompt: those are the
    /// pet's own, and this line came from outside.
    func testAnAgentLineYieldsToThePetsOwn() {
        XCTAssertLessThan(Speech.Kind.agent, Speech.Kind.wellness)
        XCTAssertLessThan(Speech.Kind.agent, Speech.Kind.refusal)
        XCTAssertLessThan(Speech.Kind.agent, Speech.Kind.reply)
        XCTAssertGreaterThan(Speech.Kind.agent, Speech.Kind.fortune)
        XCTAssertTrue(Speech(kind: .agent, face: .happy, until: start).yieldsToWork)
    }

    func testARefusalKeepsTheSlotAgainstAnAgent() {
        var speaking = Speaking()
        XCTAssertTrue(speaking.say(
            Speech(kind: .refusal, face: .dizzy, until: start.addingTimeInterval(5)), at: start
        ))
        XCTAssertFalse(speaking.say(
            Speech(kind: .agent, face: .happy, until: start.addingTimeInterval(5)), at: start
        ))
    }
}
