import XCTest
@testable import SquawkCore

final class ChirpTests: XCTestCase {
    /// A note that starts or stops at full amplitude clicks, and the click is
    /// louder than the note.
    func testNotesStartAndEndAtSilence() {
        let samples = Chirp.samples(Chirp.poke)
        XCTAssertGreaterThan(samples.count, 100)
        XCTAssertEqual(samples.first ?? 1, 0, accuracy: 0.02)
        XCTAssertEqual(samples.last ?? 1, 0, accuracy: 0.02)
    }

    func testItIsNeverLoudEnoughToStartle() {
        for notes in [Chirp.poke, Chirp.giggle] + Chirp.steps {
            for sample in Chirp.samples(notes) {
                XCTAssertLessThanOrEqual(abs(sample), 0.32, "a desk toy must not be loud")
            }
        }
    }

    func testTheLengthIsTheNotesAskedFor() {
        let samples = Chirp.samples([Chirp.Note(440, seconds: 0.5)])
        XCTAssertEqual(Double(samples.count) / Chirp.sampleRate, 0.5, accuracy: 0.01)
    }

    /// Every chirp is over before anyone could call it a jingle.
    func testEveryChirpIsShort() {
        for notes in [Chirp.poke, Chirp.giggle] + Chirp.steps {
            let seconds = notes.reduce(0) { $0 + $1.seconds }
            XCTAssertLessThan(seconds, 0.25, "\(notes)")
        }
    }

    func testTheEnvelopeRisesAndFalls() {
        XCTAssertEqual(Chirp.envelope(0, seconds: 0.1), 0, accuracy: 0.001)
        XCTAssertEqual(Chirp.envelope(0.5, seconds: 0.1), 1, accuracy: 0.001)
        XCTAssertEqual(Chirp.envelope(1, seconds: 0.1), 0, accuracy: 0.001)
    }
}

final class DanceBeatTests: XCTestCase {
    /// A loop whose bar is not exactly four beats drifts against the dance it
    /// is supposed to be driving.
    func testTheBarIsExactlyFourBeats() {
        for tempo in [1.8, 2.2, 3.0] {
            let seconds = Double(Chirp.bar(tempo: tempo).count) / Chirp.sampleRate
            XCTAssertEqual(seconds, 4 / tempo, accuracy: 0.002, "at \(tempo)")
        }
    }

    /// It plays round and round, so a loud sample at either end is a click on
    /// every repeat.
    func testItJoinsBackOntoItselfQuietly() {
        let bar = Chirp.bar()
        XCTAssertLessThan(abs(bar.last ?? 1), 0.02, "the end has to meet the start")
    }

    func testItIsNeverLouderThanAsked() {
        for sample in Chirp.bar(amplitude: 0.16) {
            XCTAssertLessThanOrEqual(abs(sample), 0.1601)
        }
    }

    /// There has to be a kick at the top of the bar, or it is not a beat.
    func testTheBarOpensOnTheOne() {
        let bar = Chirp.bar()
        let opening = bar.prefix(Int(0.1 * Chirp.sampleRate)).map(abs).max() ?? 0
        XCTAssertGreaterThan(opening, 0.05)
    }

    /// The same bar twice, or two players fall out of step with each other.
    func testItIsTheSameBarEveryTime() {
        XCTAssertEqual(Chirp.bar(), Chirp.bar())
    }
}
