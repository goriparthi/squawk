import XCTest
@testable import SquawkCore

final class SpeakableTests: XCTestCase {
    /// The words it says most are the ones every engine is worst at, and the
    /// moment you need to hear a command clearly is the moment you are
    /// deciding whether to allow it.
    func testTheCommandsItSaysMostAreSaidProperly() {
        XCTAssertEqual(Speakable.spoken("psql migrations"), "p s q l migrations")
        XCTAssertEqual(Speakable.spoken("kubectl apply"), "kube control apply")
        XCTAssertEqual(Speakable.spoken("chmod 755"), "ch mod 755")
    }

    /// "-rf" is "dash r f", not a syllable.
    func testFlagsAreSpelledOut() {
        XCTAssertEqual(Speakable.spoken("rm -rf build"), "r m dash r f build")
        XCTAssertEqual(Speakable.spoken("npm i --save"), "n p m i dash dash s a v e")
    }

    /// A word that merely starts with one of these is left alone.
    func testOnlyWholeWordsAreChanged() {
        XCTAssertEqual(Speakable.spoken("psqlrc"), "psqlrc")
        XCTAssertEqual(Speakable.spoken("formatted"), "formatted")
    }

    /// Sentences it says keep their punctuation, or everything runs together.
    func testPunctuationSurvives() {
        XCTAssertEqual(Speakable.spoken("squawk wants Bash: npm test."),
                       "squawk wants Bash: n p m test.")
    }

    func testOrdinaryWordsAreUntouched() {
        let plain = "Two waiting. Nothing looks risky."
        XCTAssertEqual(Speakable.spoken(plain), plain)
    }
}

extension SpeakableTests {
    /// An entry that maps a word to itself only strips its capitals.
    func testNothingIsSaidAsItself() {
        for (written, said) in Speakable.saidAs {
            XCTAssertNotEqual(written, said, "\(written) maps to itself")
        }
    }
}
