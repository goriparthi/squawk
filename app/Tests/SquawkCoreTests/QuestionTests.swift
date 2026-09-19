import XCTest
@testable import SquawkCore

final class QuestionTests: XCTestCase {
    /// The regression this exists to stop: "who wrote dracula" named nothing,
    /// so nothing was looked up, so a model told to admit ignorance did.
    func testAVerbNamesTheThingJustAsWellAsANoun() {
        XCTAssertEqual(Question.subject(of: "who wrote dracula"), "dracula")
        XCTAssertEqual(Question.subject(of: "who invented the telephone"), "telephone")
        XCTAssertEqual(Question.subject(of: "who founded the royal society"), "royal society")
    }

    func testItStillCatchesThePlainShapes() {
        XCTAssertEqual(Question.subject(of: "who is ada lovelace"), "ada lovelace")
        XCTAssertEqual(Question.subject(of: "tell me about canberra"), "canberra")
        XCTAssertEqual(Question.subject(of: "where is reykjavik"), "reykjavik")
    }

    /// The article belongs to the question, not to the thing.
    func testTheArticleIsNotPartOfTheName() {
        XCTAssertEqual(Question.subject(of: "what is a barometer"), "barometer")
        XCTAssertEqual(Question.subject(of: "what is the eiffel tower"), "eiffel tower")
    }

    /// Nothing to look up in a question about them, the sky, or the clock.
    func testQuestionsWithNoSubjectAreLeftAlone() {
        XCTAssertNil(Question.subject(of: "what did I approve today"))
        XCTAssertNil(Question.subject(of: "what time is it"))
        XCTAssertNil(Question.subject(of: "what is it"))
        XCTAssertNil(Question.subject(of: "who is going to tell me what all of this is even for"))
    }
}
