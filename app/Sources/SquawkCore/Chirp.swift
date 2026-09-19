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

    /// One bar of a plain four to the floor, built to loop seamlessly: kick on
    /// the ones, a clap on the backbeat, hats on the eighths and a two note
    /// bass pulse underneath. Synthesised at the tempo the routine actually
    /// runs at, so the pet is dancing to this rather than near it.
    ///
    /// Deliberately small and dry. A desk toy playing a full arrangement is a
    /// desk toy somebody turns off.
    public static func bar(tempo: Double = 2.2, amplitude: Double = 0.16) -> [Float] {
        let beat = 1 / max(0.5, tempo)
        let count = Int(beat * 4 * sampleRate)
        var mix = [Double](repeating: 0, count: count)
        var noise = Noise()

        func place(_ voice: [Double], at seconds: Double) {
            let start = Int(seconds * sampleRate)
            for (offset, value) in voice.enumerated() where start + offset < count {
                mix[start + offset] += value
            }
        }

        for step in [0.0, 2.0] { place(kick(), at: step * beat) }
        // The backbeat is the half of this that makes it pop rather than techno.
        for step in [1.0, 3.0] { place(clap(&noise), at: step * beat) }
        for eighth in stride(from: 0.0, to: 4.0, by: 0.5) {
            place(hat(&noise, open: eighth.truncatingRemainder(dividingBy: 1) != 0),
                  at: eighth * beat)
        }
        // A two note figure, low, so the bar has somewhere to go and comes back.
        for (step, note) in [(0.0, 55.0), (1.5, 55.0), (2.0, 73.42), (3.5, 65.41)] {
            place(bass(note, seconds: beat * 0.45), at: step * beat)
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
