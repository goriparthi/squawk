import Foundation

/// The little noises the pet makes, as samples rather than as files. Synthesised
/// because a desk toy that ships a folder of beeps is carrying weight it does
/// not need, and because a note computed here can be tested.
public enum Chirp {
    /// Plenty for a chirp, and a quarter of the data of the usual rate.
    public static let sampleRate: Double = 22_050

    /// One note, optionally sliding from one pitch to another.
    public struct Note: Sendable, Equatable {
        public let from: Double
        public let to: Double
        public let seconds: Double

        public init(_ from: Double, to: Double? = nil, seconds: Double) {
            self.from = from
            self.to = to ?? from
            self.seconds = seconds
        }
    }

    /// How long the edges take. Without this a note starts and stops at full
    /// amplitude, and the click that makes is louder than the note.
    public static let edge: Double = 0.008

    /// A soft square-ish voice: the fundamental with a little of the third
    /// harmonic, which is what makes it read as a small machine rather than a
    /// test tone.
    public static func samples(_ notes: [Note], amplitude: Double = 0.22) -> [Float] {
        var samples: [Float] = []
        for note in notes {
            let count = max(1, Int(note.seconds * sampleRate))
            var phase = 0.0
            for index in 0..<count {
                let progress = Double(index) / Double(count)
                let frequency = note.from + (note.to - note.from) * progress
                phase += 2 * .pi * frequency / sampleRate
                let value = sin(phase) + 0.18 * sin(phase * 3)
                samples.append(Float(value * amplitude * envelope(progress, seconds: note.seconds)))
            }
        }
        return samples
    }

    /// Up quickly, down gently, and never starting or ending anywhere but zero.
    static func envelope(_ progress: Double, seconds: Double) -> Double {
        let edgeShare = min(0.45, edge / max(seconds, 0.001))
        if progress < edgeShare { return progress / edgeShare }
        let tail = 1 - progress
        if tail < edgeShare * 3 { return max(0, tail / (edgeShare * 3)) }
        return 1
    }

    // MARK: - A beat to dance to

    /// One hit: where in the bar, and how hard.
    public struct Hit: Sendable, Equatable {
        public let beat: Double
        public let strength: Double
        public init(_ beat: Double, _ strength: Double = 1) {
            self.beat = beat
            self.strength = strength
        }
    }

    /// A note in the bass figure.
    public struct Step: Sendable, Equatable {
        public let beat: Double
        public let note: Double
        public init(_ beat: Double, _ note: Double) {
            self.beat = beat
            self.note = note
        }
    }

    /// A character's own groove. Everyone dances, but nobody dances the same:
    /// the pattern, the tempo and the notes underneath it are all theirs.
    public struct Groove: Sendable, Equatable {
        public let tempo: Double
        public let kicks: [Hit]
        public let claps: [Hit]
        /// Spacing of the hats in beats. Zero leaves them out entirely.
        public let hatEvery: Double
        /// How far the offbeats lean late, as a share of the gap. A shuffle.
        public let swing: Double
        public let bass: [Step]
        /// How much the hats and clap cut through. Quiet for a sparse groove.
        public let brightness: Double

        public init(tempo: Double, kicks: [Hit], claps: [Hit], hatEvery: Double,
                    swing: Double = 0, bass: [Step], brightness: Double = 1) {
            self.tempo = tempo
            self.kicks = kicks
            self.claps = claps
            self.hatEvery = hatEvery
            self.swing = swing
            self.bass = bass
            self.brightness = brightness
        }
    }

    /// Who dances how. Written to the tagline each of them carries, because a
    /// groove is a character note and not a setting.
    public static func groove(for persona: String) -> Groove {
        switch persona {
        case "chalk":
            // Clean desk: the fewest hits that still swing, and space around
            // every one of them.
            return Groove(tempo: 2.0,
                          kicks: [Hit(0), Hit(2)],
                          claps: [Hit(2)],
                          hatEvery: 1, swing: 0,
                          bass: [Step(0, 98.0), Step(2, 110.0)],
                          brightness: 0.7)
        case "ember":
            // Runs hot: a double kick pushing at the end of every other bar.
            return Groove(tempo: 2.5,
                          kicks: [Hit(0), Hit(1.75, 0.8), Hit(2), Hit(3.5, 0.7)],
                          claps: [Hit(1), Hit(3)],
                          hatEvery: 0.25, swing: 0,
                          bass: [Step(0, 65.41), Step(1.5, 65.41), Step(2, 87.31), Step(3.5, 77.78)],
                          brightness: 1.15)
        case "moss":
            // Slow and thorough: half time, the clap landing once and late.
            return Groove(tempo: 1.7,
                          kicks: [Hit(0), Hit(2.5, 0.85)],
                          claps: [Hit(2)],
                          hatEvery: 0.5, swing: 0.12,
                          bass: [Step(0, 49.0), Step(2, 58.27)],
                          brightness: 0.8)
        case "dusk":
            // Works nights: the bass on the offbeat, which is what makes a
            // room move at two in the morning.
            return Groove(tempo: 2.2,
                          kicks: [Hit(0), Hit(1), Hit(2), Hit(3)],
                          claps: [Hit(1), Hit(3)],
                          hatEvery: 0.5, swing: 0,
                          bass: [Step(0.5, 55.0), Step(1.5, 55.0),
                                 Step(2.5, 73.42), Step(3.5, 73.42)],
                          brightness: 0.95)
        case "rust":
            // Been here longer: shuffled, the way everything used to be.
            return Groove(tempo: 1.9,
                          kicks: [Hit(0), Hit(2), Hit(3.33, 0.7)],
                          claps: [Hit(1), Hit(3)],
                          hatEvery: 0.5, swing: 0.28,
                          bass: [Step(0, 73.42), Step(1.66, 82.41), Step(3, 61.74)],
                          brightness: 0.85)
        case "soot":
            // Says nothing: almost nothing on top, and a long note underneath
            // doing all the work.
            return Groove(tempo: 1.8,
                          kicks: [Hit(0), Hit(2, 0.9)],
                          claps: [],
                          hatEvery: 2, swing: 0,
                          bass: [Step(0, 41.20), Step(2, 43.65)],
                          brightness: 0.5)
        case "ruby":
            // Fast and loud: sixteenths, four on the floor, no room to think.
            return Groove(tempo: 2.9,
                          kicks: [Hit(0), Hit(1), Hit(2), Hit(3)],
                          claps: [Hit(1), Hit(3), Hit(3.75, 0.6)],
                          hatEvery: 0.25, swing: 0,
                          bass: [Step(0, 98.0), Step(0.75, 98.0), Step(2, 130.81),
                                 Step(2.75, 116.54)],
                          brightness: 1.25)
        default:
            // Pip, and anyone new: the plain one everything else is a variation on.
            return Groove(tempo: 2.2,
                          kicks: [Hit(0), Hit(2)],
                          claps: [Hit(1), Hit(3)],
                          hatEvery: 0.5, swing: 0,
                          bass: [Step(0, 55.0), Step(1.5, 55.0),
                                 Step(2, 73.42), Step(3.5, 65.41)],
                          brightness: 1)
        }
    }

    /// One bar of that groove, built to loop seamlessly. Synthesised at the
    /// tempo the routine actually runs at, so the pet is dancing to this
    /// rather than near it.
    ///
    /// Deliberately small and dry. A desk toy playing a full arrangement is a
    /// desk toy somebody turns off.
    public static func bar(_ groove: Groove = groove(for: "pip"),
                           amplitude: Double = 0.16) -> [Float] {
        let beat = 1 / max(0.5, groove.tempo)
        let count = Int(beat * 4 * sampleRate)
        var mix = [Double](repeating: 0, count: count)
        var noise = Noise()

        func place(_ voice: [Double], at seconds: Double, level: Double = 1) {
            let start = Int(seconds * sampleRate)
            for (offset, value) in voice.enumerated() where start + offset < count {
                mix[start + offset] += value * level
            }
        }

        for hit in groove.kicks { place(kick(), at: hit.beat * beat, level: hit.strength) }
        for hit in groove.claps {
            place(clap(&noise), at: hit.beat * beat, level: hit.strength * groove.brightness)
        }
        if groove.hatEvery > 0 {
            for tick in stride(from: 0.0, to: 4.0, by: groove.hatEvery) {
                let offbeat = tick.truncatingRemainder(dividingBy: 1) != 0
                // Swing pushes the offbeats late, which is the whole of a shuffle.
                let when = offbeat ? tick + groove.swing : tick
                place(hat(&noise, open: offbeat), at: when * beat, level: groove.brightness)
            }
        }
        for step in groove.bass {
            place(bass(step.note, seconds: beat * 0.45), at: step.beat * beat)
        }

        let peak = mix.map(abs).max() ?? 1
        let scale = peak > 0 ? amplitude / peak : 0
        return mix.map { Float($0 * scale) }
    }

    /// A pitch dropping into the floor, which is what a kick drum is.
    private static func kick(seconds: Double = 0.12) -> [Double] {
        let count = Int(seconds * sampleRate)
        var phase = 0.0
        return (0..<count).map { index in
            let progress = Double(index) / Double(count)
            let frequency = 120 - 75 * min(1, progress * 3)
            phase += 2 * .pi * frequency / sampleRate
            return sin(phase) * pow(1 - progress, 2.2)
        }
    }

    private static func clap(_ noise: inout Noise, seconds: Double = 0.1) -> [Double] {
        let count = Int(seconds * sampleRate)
        return (0..<count).map { index in
            let progress = Double(index) / Double(count)
            // Two hits a few milliseconds apart, which is what makes a clap
            // read as hands rather than as static.
            let second = progress > 0.12 ? 1.0 : 0.55
            return noise.next() * pow(1 - progress, 3.4) * second * 0.7
        }
    }

    private static func hat(_ noise: inout Noise, open: Bool) -> [Double] {
        let count = Int((open ? 0.05 : 0.028) * sampleRate)
        return (0..<count).map { index in
            let progress = Double(index) / Double(count)
            return noise.next() * pow(1 - progress, 5) * (open ? 0.16 : 0.26)
        }
    }

    private static func bass(_ frequency: Double, seconds: Double) -> [Double] {
        let count = Int(seconds * sampleRate)
        var phase = 0.0
        return (0..<count).map { index in
            let progress = Double(index) / Double(count)
            phase += 2 * .pi * frequency / sampleRate
            // A little of the octave, so it carries on a small speaker.
            return (sin(phase) + 0.3 * sin(phase * 2)) * pow(1 - progress, 1.6) * 0.5
        }
    }

    /// Repeatable noise, so a test sees the same bar twice and the loop is not
    /// at the mercy of the system generator.
    struct Noise {
        private var state: UInt64 = 0x5EED_1234_ABCD_9F01
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(Int64(bitPattern: state >> 11)) / Double(1 << 52) - 1
        }
    }

    /// Prodded: one short blip, and nothing more. It happens often.
    public static let poke = [Note(760, seconds: 0.07)]
    /// Tickled: two notes going up, which is what a laugh does.
    public static let giggle = [Note(620, to: 720, seconds: 0.07),
                                Note(880, to: 990, seconds: 0.09)]
    /// Had enough: a tone falling away, which is a small machine sighing.
    public static let grumble = [Note(330, to: 150, seconds: 0.22)]
    /// A dance step. Cycles so a routine is a phrase rather than one note over
    /// and over: a pentatonic run, which cannot land on a sour note.
    public static let steps: [[Note]] = [523, 587, 659, 784, 880].map {
        [Note($0, seconds: 0.075)]
    }
}
