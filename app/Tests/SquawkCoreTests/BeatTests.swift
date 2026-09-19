import XCTest
@testable import SquawkCore

final class BeatTests: XCTestCase {
    /// A steady kick at 120bpm should be found, and found at 120.
    func testItFindsASteadyBeat() {
        var detector = BeatDetector()
        var beats = 0
        let period = 0.5
        for tick in 0..<400 {
            let now = Double(tick) * 0.02
            let sinceBeat = now.truncatingRemainder(dividingBy: period)
            let kick = sinceBeat < 0.04 ? 0.9 : 0.18
            if detector.track(spectrum(low: kick), at: now) { beats += 1 }
        }
        XCTAssertGreaterThan(beats, 12, "missed most of a steady kick")
        XCTAssertNotNil(detector.tempo)
        XCTAssertEqual(detector.tempo ?? 0, 1 / period, accuracy: 0.15)
    }

    /// Sustained bass at a constant level is not a beat, however loud. This
    /// includes while the detector is still learning what the level is.
    func testALoudFlatToneIsNotABeat() {
        var detector = BeatDetector()
        var beats = 0
        for tick in 0..<400 {
            if detector.track(spectrum(low: 0.85), at: Double(tick) * 0.02) { beats += 1 }
        }
        XCTAssertEqual(beats, 0, "a held note read as \(beats) beats")
    }

    func testSilenceHasNoBeat() {
        var detector = BeatDetector()
        for tick in 0..<200 {
            XCTAssertFalse(detector.track(.silent, at: Double(tick) * 0.02))
        }
        XCTAssertNil(detector.tempo)
    }

    /// Two hits closer together than the refractory period are one beat, or a
    /// snare flam doubles the tempo.
    func testItWillNotFireTwiceInAnInstant() {
        var detector = BeatDetector()
        for tick in 0..<60 {
            _ = detector.track(spectrum(low: 0.15), at: Double(tick) * 0.02)
        }
        let first = detector.track(spectrum(low: 0.9), at: 1.2)
        let second = detector.track(spectrum(low: 0.9), at: 1.2 + BeatDetector.refractory / 2)
        XCTAssertTrue(first)
        XCTAssertFalse(second)
    }

    /// A gap means a different song, not a very slow tempo.
    func testALongGapForgetsTheTempo() {
        var detector = BeatDetector()
        for tick in 0..<400 {
            let now = Double(tick) * 0.02
            let kick = now.truncatingRemainder(dividingBy: 0.5) < 0.04 ? 0.9 : 0.18
            _ = detector.track(spectrum(low: kick), at: now)
        }
        XCTAssertNotNil(detector.tempo)
        _ = detector.track(spectrum(low: 0.9), at: 40)
        XCTAssertNil(detector.tempo, "the tempo survived a forty second gap")
    }

    /// The movement peaks on the beat and is gone before the next one.
    func testThePulseLandsOnTheBeatAndFades() {
        XCTAssertEqual(BeatDetector.pulse(since: -1), 0)
        XCTAssertGreaterThan(BeatDetector.pulse(since: 0.02), 0.8)
        XCTAssertLessThan(BeatDetector.pulse(since: 0.3), 0.2)
        XCTAssertEqual(BeatDetector.pulse(since: 0.6), 0)
    }

    /// Built with linear energy, which is what the detector reads, rather than
    /// with the compressed values the bars are drawn from.
    private func spectrum(low: Double) -> Spectrum {
        Spectrum(bands: [low, low * 0.8, 0.2, 0.15, 0.1],
                 energy: [low, low * 0.8, 0.2, 0.15, 0.1],
                 level: max(0.2, low))
    }
}

final class DanceableTempoTests: XCTestCase {
    /// Whatever is detected, the routine runs somewhere between a slow sway and
    /// a fast bounce. A dance at 40 or 220 beats a minute reads as broken.
    func testAnyTempoBecomesOneWorthDancingAt() {
        for detected in stride(from: 0.2, through: 8.0, by: 0.05) {
            let tempo = Dance.danceable(detected)
            XCTAssertGreaterThanOrEqual(tempo, 1.4, "too slow for \(detected)")
            XCTAssertLessThanOrEqual(tempo, 3.2, "too fast for \(detected)")
        }
    }

    /// Halving and doubling only, so the routine still lands on the music's
    /// beats rather than near them.
    func testItOnlyHalvesAndDoubles() {
        for detected in [0.75, 1.1, 4.4, 6.0] {
            let tempo = Dance.danceable(detected)
            let ratio = tempo / detected
            let doublings = (log2(ratio)).rounded()
            XCTAssertEqual(log2(ratio), doublings, accuracy: 0.0001,
                           "\(detected) was not a power of two away from \(tempo)")
        }
    }

    func testNothingDetectedKeepsItsOwnTempo() {
        XCTAssertEqual(Dance.danceable(nil), Dance.tempo)
        XCTAssertEqual(Dance.danceable(0), Dance.tempo)
        XCTAssertEqual(Dance.danceable(.infinity), Dance.tempo)
    }
}

final class GrooveTests: XCTestCase {
    /// It moves on both sides of its body and in both directions, or it is a
    /// twitch rather than a groove.
    func testItActuallyMovesInEveryDirection() {
        let samples = stride(from: 0.0, through: 4.0, by: 0.05).map(Dance.groove(beat:))
        XCTAssertGreaterThan(samples.map(\.sway).max() ?? 0, 4)
        XCTAssertLessThan(samples.map(\.sway).min() ?? 0, -4)
        XCTAssertGreaterThan(samples.map(\.bob).max() ?? 0, 0.02)
        XCTAssertGreaterThan(samples.map(\.headRoll).max() ?? 0, 4)
    }

    /// The arms take turns, the way they do when anyone sways to anything.
    func testTheArmsAlternate() {
        let apart = stride(from: 0.0, through: 4.0, by: 0.05)
            .map { abs(Dance.groove(beat: $0).leftShoulder - Dance.groove(beat: $0).rightShoulder) }
        XCTAssertGreaterThan(apart.max() ?? 0, 30)
    }

    /// A knee that bends backward is a broken knee, in a groove as anywhere.
    func testKneesNeverBendBackward() {
        for beat in stride(from: 0.0, through: 8.0, by: 0.02) {
            let pose = Dance.groove(beat: beat)
            XCTAssertGreaterThanOrEqual(pose.leftKnee, 0, "at \(beat)")
            XCTAssertGreaterThanOrEqual(pose.rightKnee, 0, "at \(beat)")
        }
    }

    /// It repeats every two beats, so the sway is in time with the music rather
    /// than drifting against it.
    func testItRepeatsEveryTwoBeats() {
        for beat in stride(from: 0.0, through: 2.0, by: 0.1) {
            let now = Dance.groove(beat: beat)
            let later = Dance.groove(beat: beat + 2)
            XCTAssertEqual(now.sway, later.sway, accuracy: 0.001, "at \(beat)")
            XCTAssertEqual(now.leftShoulder, later.leftShoulder, accuracy: 0.001, "at \(beat)")
        }
    }

    /// Laid over what the pet was doing rather than replacing it.
    func testItBlendsRatherThanReplaces() {
        var standing = Pose3D()
        standing.lean = 10
        let blended = standing.blended(with: Dance.groove(beat: 0.25), amount: 0.5)
        XCTAssertLessThan(blended.lean, 10)
        XCTAssertGreaterThan(blended.lean, 0)
        XCTAssertEqual(standing.blended(with: Dance.groove(beat: 0.25), amount: 0).lean, 10)
    }
}
