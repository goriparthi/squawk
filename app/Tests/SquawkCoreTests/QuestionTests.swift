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

final class LookupRelevanceTests: XCTestCase {
    /// The one that made this necessary: searching for the tallest mountain in
    /// Colorado returns an article about buildings in Denver, and a model
    /// grounded on that will tell you about buildings.
    func testAnArticleAboutSomethingElseIsRefused() {
        XCTAssertFalse(Question.isRelevant(title: "List of tallest buildings in Denver",
                                           to: "tallest mountain in Colorado"))
    }

    func testAnArticleAboutTheThingIsKept() {
        XCTAssertTrue(Question.isRelevant(title: "Denver", to: "what is the population of Denver"))
        XCTAssertTrue(Question.isRelevant(title: "Anthropic", to: "who is the CEO of Anthropic"))
        XCTAssertTrue(Question.isRelevant(title: "Mount Elbert", to: "how tall is mount elbert"))
    }

    /// Small words carry no subject and must not make a title look relevant.
    func testTheSmallWordsAreIgnored() {
        XCTAssertEqual(Question.words(in: "what is the population of Denver"),
                       ["population", "denver"])
        XCTAssertFalse(Question.isRelevant(title: "The A of In", to: "anything at all"))
    }
}
