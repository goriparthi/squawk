import Foundation

/// What the pet shows while something is playing: a few bands of level, already
/// smoothed and ready to draw. Kept apart from the audio plumbing so the maths
/// can be tested without a sound card.
public struct Spectrum: Sendable, Equatable {
    /// Low to high. Five is what reads at pet size; more turns into a smear.
    public static let bandCount = 5

    /// Compressed for drawing: decibels mapped into 0 to 1 so the bars use
    /// their whole height at ordinary listening levels.
    public var bands: [Double]
    /// The same bands before compression, as linear amplitude. Onset detection
    /// needs ratios between one moment and the next, and compressing into a
    /// clipped 0 to 1 destroys exactly the ratios it is looking for: against
    /// real music every display band sat pinned at 1.0 and no beat could ever
    /// stand out from its own average.
    public var energy: [Double]
    /// Overall loudness, for deciding whether anything is playing at all.
    public var level: Double

    public init(bands: [Double] = Array(repeating: 0, count: Spectrum.bandCount),
                energy: [Double]? = nil,
                level: Double = 0) {
        self.bands = bands
        self.energy = energy ?? bands
        self.level = level
    }

    public static let silent = Spectrum()

    public var isSilent: Bool { level < Spectrum.silenceFloor }

    /// Below this it is room noise or a paused track, not music. A meter that
    /// twitches at silence looks broken.
    public static let silenceFloor: Double = 0.012
}

/// Turns FFT magnitudes into something worth drawing. The hard parts are that
/// hearing is logarithmic in both axes, and that a meter which tracks the
/// signal exactly looks like noise: it has to jump to a peak and fall away.
public enum SpectrumMeter {
    /// Band edges in Hz, spaced the way octaves are rather than evenly, because
    /// half of an evenly spaced spectrum is cymbals.
    public static let edges: [Double] = [40, 160, 500, 1_400, 4_000, 14_000]

    /// Which bin range of a spectrum each band covers.
    public static func bins(forBandCount count: Int = Spectrum.bandCount,
                            sampleRate: Double, fftSize: Int) -> [Range<Int>] {
        let resolution = sampleRate / Double(fftSize)
        let usable = fftSize / 2
        return (0..<count).map { band in
            let low = Int((edges[band] / resolution).rounded(.down))
            let high = Int((edges[band + 1] / resolution).rounded(.up))
            let start = min(max(1, low), usable - 1)
            let end = min(max(start + 1, high), usable)
            return start..<end
        }
    }

    /// Magnitudes to bars. Each band takes its loudest bin rather than its
    /// average: an average over a wide band is dominated by how many bins it
    /// happens to contain, so the high bands would always read quiet.
    public static func bands(from magnitudes: [Float], bins: [Range<Int>])
        -> (display: [Double], energy: [Double]) {
        var display: [Double] = []
        var energy: [Double] = []
        for range in bins {
            var peak: Float = 0
            for index in range where index < magnitudes.count {
                peak = max(peak, magnitudes[index])
            }
            energy.append(Double(peak))
            display.append(loudness(Double(peak)))
        }
        return (display, energy)
    }

    /// Amplitude to something eyes agree with: decibels, clipped to a window
    /// that puts ordinary listening levels across the full height.
    public static func loudness(_ amplitude: Double) -> Double {
        guard amplitude > 0 else { return 0 }
        let decibels = 20 * log10(amplitude)
        let floor = -72.0
        let ceiling = 0.0
        return min(1, max(0, (decibels - floor) / (ceiling - floor)))
    }

    /// Jumps to a rise and falls away from it. A meter that follows the signal
    /// down as fast as it goes up flickers; one that follows it up slowly
    /// misses every transient, which is the only interesting part.
    public static func follow(
        _ current: Double, toward target: Double, dt: Double,
        attack: Double = 0.02, release: Double = 0.28
    ) -> Double {
        guard dt > 0 else { return current }
        let rising = target > current
        let time = rising ? attack : release
        let approach = 1 - pow(2, -dt / max(0.001, time))
        return current + (target - current) * approach
    }

    public static func follow(
        _ current: Spectrum, toward target: Spectrum, dt: Double
    ) -> Spectrum {
        var next = Spectrum()
        next.bands = zip(current.bands, target.bands).map {
            follow($0, toward: $1, dt: dt)
        }
        // Loudness settles more slowly than the bars, because it decides
        // whether the headphones are on at all and they must not flicker.
        next.level = follow(current.level, toward: target.level, dt: dt,
                            attack: 0.05, release: 0.9)
        return next
    }
}
