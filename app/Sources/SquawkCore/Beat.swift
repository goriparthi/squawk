import Foundation

/// Finds the beat in a stream of spectra, so the pet can move on it rather than
/// on a timer that happens to be running while music plays.
///
/// Onset detection on the low bands: a beat is a sudden rise in energy against
/// what the last second or so has been doing. Thresholding against an absolute
/// level instead would fire constantly on loud music and never on quiet music.
public struct BeatDetector: Sendable {
    /// How much above the running average counts as a hit. Too low and it
    /// triggers on sustained bass, too high and it misses everything quiet.
    public static let threshold: Double = 1.42
    /// Nothing can be a beat within this of the last one. 250ms puts the
    /// ceiling at 240bpm, which is faster than anything worth dancing to.
    public static let refractory: TimeInterval = 0.25
    /// How long the running average remembers.
    public static let memory: TimeInterval = 1.4
    /// Tempo is only reported once this many intervals agree.
    public static let intervalsForTempo = 4
    /// Blocks of history needed before anything can be called a beat. At the
    /// rate audio arrives this is a little under a second.
    public static let warmupBlocks = 15
    /// How much of each new block goes into the running average. A little under
    /// a second and a half of history at the rate audio arrives.
    public static let weight: Double = 0.028

    private var average: Double?
    private var lastBeat: TimeInterval = -1
    private var intervals: [TimeInterval] = []
    /// An onset is a rise against recent history, so there has to be some. The
    /// running average climbs from zero, and while it climbs everything looks
    /// like a rise: a held note fired four times before this.
    private var warmup = 0

    public init() {}

    /// The tempo in beats per second, once there is enough agreement to say.
    /// Nil while it is still listening.
    public private(set) var tempo: Double?

    /// Feeds one spectrum. True when this is the moment of a beat.
    public mutating func track(_ spectrum: Spectrum, at now: TimeInterval) -> Bool {
        // The beat lives in the bottom two bands: a kick and a bass note. The
        // top bands are cymbals and consonants, which are not the pulse.
        let energy = spectrum.bands.prefix(2).reduce(0, +) / 2
        // Seeded with the first block rather than climbing from zero. A running
        // average that starts at zero ramps up through whatever is playing, and
        // while it ramps every sample looks like a rise: a held note fired
        // several times before the first beat of real music.
        let history = average ?? energy
        defer { average = history + (energy - history) * Self.weight }

        warmup += 1
        guard warmup > Self.warmupBlocks else { return false }
        guard !spectrum.isSilent, history > 0.02 else { return false }
        guard energy > history * Self.threshold else { return false }
        if lastBeat >= 0 {
            let gap = now - lastBeat
            guard gap >= Self.refractory else { return false }
            // Keep a short history and take the middle of it, so one missed
            // beat or one spurious hit does not move the tempo.
            if gap < 2 {
                intervals.append(gap)
                if intervals.count > 8 { intervals.removeFirst() }
                if intervals.count >= Self.intervalsForTempo {
                    let sorted = intervals.sorted()
                    tempo = 1 / sorted[sorted.count / 2]
                }
            } else {
                // A long gap means the music changed or stopped; start again
                // rather than averaging across two different songs.
                intervals.removeAll()
                tempo = nil
            }
        }
        lastBeat = now
        return true
    }

    /// Nothing is playing any more.
    public mutating func reset() {
        average = nil
        warmup = 0
        lastBeat = -1
        intervals.removeAll()
        tempo = nil
    }

    /// How hard the pet moves on a beat, fading over the moments after it. A
    /// step function looks like a glitch; this is a body absorbing a hit.
    public static func pulse(since beat: TimeInterval) -> Double {
        guard beat >= 0, beat < 0.42 else { return 0 }
        let decay = exp(-beat * 7)
        // A quick rise, so the top of the movement lands on the beat rather
        // than just after it.
        let rise = min(1, beat / 0.02)
        return rise * decay
    }
}
