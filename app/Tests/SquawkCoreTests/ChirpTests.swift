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
