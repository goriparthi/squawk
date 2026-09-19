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
    func testEveryBarIsExactlyFourBeats() {
        for persona in Cast.all {
            let groove = Chirp.groove(for: persona.id)
            let seconds = Double(Chirp.bar(groove).count) / Chirp.sampleRate
            XCTAssertEqual(seconds, 4 / groove.tempo, accuracy: 0.002, persona.name)
        }
    }

    /// It plays round and round, so a loud sample at either end is a click on
    /// every repeat.
    func testEveryBarJoinsBackOntoItselfQuietly() {
        for persona in Cast.all {
            let bar = Chirp.bar(Chirp.groove(for: persona.id))
            XCTAssertLessThan(abs(bar.last ?? 1), 0.03, persona.name)
        }
    }

    func testNoneIsLouderThanAsked() {
        for persona in Cast.all {
            for sample in Chirp.bar(Chirp.groove(for: persona.id), amplitude: 0.16) {
                XCTAssertLessThanOrEqual(abs(sample), 0.1601, persona.name)
            }
        }
    }

    /// The whole point: eight characters, eight grooves. Two that happen to
    /// come out identical are a copied line, not a character.
    func testEveryCharacterDancesToSomethingOfItsOwn() {
        var heard: [String: [Float]] = [:]
        for persona in Cast.all {
            let bar = Chirp.bar(Chirp.groove(for: persona.id))
            for (name, other) in heard {
                XCTAssertNotEqual(bar, other, "\(persona.name) dances exactly like \(name)")
            }
            heard[persona.name] = bar
        }
        XCTAssertEqual(heard.count, Cast.all.count)
    }

    /// Tempo is part of the character, so they must not all share one.
    func testTheTemposDiffer() {
        let tempos = Set(Cast.all.map { Chirp.groove(for: $0.id).tempo })
        XCTAssertGreaterThanOrEqual(tempos.count, 5, "eight characters at one tempo is one character")
    }

    /// There has to be a kick at the top of the bar, or it is not a beat.
    func testEveryBarOpensOnTheOne() {
        for persona in Cast.all {
            let bar = Chirp.bar(Chirp.groove(for: persona.id))
            let opening = bar.prefix(Int(0.1 * Chirp.sampleRate)).map(abs).max() ?? 0
            XCTAssertGreaterThan(opening, 0.04, persona.name)
        }
    }

    /// The same bar twice, or two players fall out of step with each other.
    func testItIsTheSameBarEveryTime() {
        XCTAssertEqual(Chirp.bar(), Chirp.bar())
    }

    /// Anyone new gets the plain one rather than silence.
    func testAnUnknownCharacterStillDances() {
        XCTAssertFalse(Chirp.bar(Chirp.groove(for: "nobody")).isEmpty)
    }
}
