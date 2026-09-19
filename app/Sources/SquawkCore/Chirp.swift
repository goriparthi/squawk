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

    /// Prodded: one short blip, and nothing more. It happens often.
    public static let poke = [Note(760, seconds: 0.07)]
    /// Tickled: two notes going up, which is what a laugh does.
    public static let giggle = [Note(620, to: 720, seconds: 0.07),
                                Note(880, to: 990, seconds: 0.09)]
    /// A dance step. Cycles so a routine is a phrase rather than one note over
    /// and over: a pentatonic run, which cannot land on a sour note.
    public static let steps: [[Note]] = [523, 587, 659, 784, 880].map {
        [Note($0, seconds: 0.075)]
    }
}
