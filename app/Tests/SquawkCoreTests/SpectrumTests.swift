import XCTest
@testable import SquawkCore

final class SpectrumTests: XCTestCase {
    private let sampleRate = 48_000.0
    private let fftSize = 1_024

    func testBandsCoverTheAudibleRangeInOrder() {
        let ranges = SpectrumMeter.bins(sampleRate: sampleRate, fftSize: fftSize)
        XCTAssertEqual(ranges.count, Spectrum.bandCount)
        for (index, range) in ranges.enumerated() {
            XCTAssertFalse(range.isEmpty, "band \(index) covers no bins")
            XCTAssertGreaterThanOrEqual(range.lowerBound, 1, "bin 0 is DC, not sound")
            XCTAssertLessThanOrEqual(range.upperBound, fftSize / 2)
        }
        for index in 1..<ranges.count {
            XCTAssertGreaterThanOrEqual(ranges[index].lowerBound, ranges[index - 1].lowerBound)
        }
    }

    /// A tone should light its own band and leave the others dark.
    func testAToneLightsOnlyItsOwnBand() {
        let ranges = SpectrumMeter.bins(sampleRate: sampleRate, fftSize: fftSize)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        // 1kHz lands in the third band, 500 to 1400.
        let bin = Int(1_000 / (sampleRate / Double(fftSize)))
        magnitudes[bin] = 0.2

        let bands = SpectrumMeter.bands(from: magnitudes, bins: ranges).display
        XCTAssertGreaterThan(bands[2], 0.3, "the tone's own band stayed dark")
        for (index, value) in bands.enumerated() where index != 2 {
            XCTAssertEqual(value, 0, accuracy: 0.001, "band \(index) lit for a 1kHz tone")
        }
    }

    /// Averaging across a band makes the wide high bands read quiet whatever is
    /// in them, so each band takes its loudest bin.
    func testAWideBandIsNotDilutedByItsEmptyBins() {
        let ranges = SpectrumMeter.bins(sampleRate: sampleRate, fftSize: fftSize)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        magnitudes[ranges[4].lowerBound + 3] = 0.2
        let bands = SpectrumMeter.bands(from: magnitudes, bins: ranges).display
        XCTAssertGreaterThan(bands[4], 0.3)
    }

    func testLoudnessIsLogarithmic() {
        XCTAssertEqual(SpectrumMeter.loudness(0), 0)
        // Halving the amplitude is a fixed drop in decibels wherever you start,
        // so the same halving should cost the same height at any level.
        let dropHigh = SpectrumMeter.loudness(0.4) - SpectrumMeter.loudness(0.2)
        let dropLow = SpectrumMeter.loudness(0.1) - SpectrumMeter.loudness(0.05)
        XCTAssertEqual(dropHigh, dropLow, accuracy: 0.01)
        XCTAssertEqual(SpectrumMeter.loudness(1.0), 1.0, accuracy: 0.001)
        // Ordinary listening levels have to sit inside the window, not pinned
        // at the top of it. A quarter of full scale is not "as loud as it gets".
        XCTAssertLessThan(SpectrumMeter.loudness(0.25), 0.9)
        XCTAssertGreaterThan(SpectrumMeter.loudness(0.25), 0.5)
    }

    /// Fast up, slow down. The other way round and every transient is missed.
    func testTheMeterJumpsUpAndFallsAway() {
        let rise = SpectrumMeter.follow(0, toward: 1, dt: 0.02)
        let fall = SpectrumMeter.follow(1, toward: 0, dt: 0.02)
        XCTAssertGreaterThan(rise, 0.4, "should jump to a peak")
        XCTAssertGreaterThan(fall, 0.9, "should fall away, not drop")
    }

    func testSilenceIsSilent() {
        XCTAssertTrue(Spectrum.silent.isSilent)
        var playing = Spectrum()
        playing.level = 0.4
        XCTAssertFalse(playing.isSilent)
    }

    /// Whether anything is playing has to settle slowly, or the headphones
    /// flicker on and off between beats.
    func testTheOverallLevelSettlesSlowerThanTheBars() {
        var meter = Spectrum()
        var loud = Spectrum(bands: Array(repeating: 1, count: Spectrum.bandCount), level: 1)
        meter = SpectrumMeter.follow(meter, toward: loud, dt: 0.05)
        loud = Spectrum.silent
        let barsFirst = SpectrumMeter.follow(meter, toward: loud, dt: 0.4)
        XCTAssertLessThan(barsFirst.bands[0], barsFirst.level,
                          "the bars should fall away before the headphones do")
    }
}
