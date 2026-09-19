import AVFoundation
import AppKit
import SquawkCore

/// The pet's little noises. Synthesised from `Chirp`, wrapped in a WAV header
/// once and kept, so prodding it does not allocate anything.
///
/// Quiet on purpose, and silent whenever something else is making sound: a toy
/// that beeps over your music, or over its own voice, gets switched off.
@MainActor
enum Chirps {
    private static var cache: [String: Data] = [:]
    private static var players: [AVAudioPlayer] = []
    /// Two chirps on top of each other is a fault noise, not a pet.
    private static var lastAt = Date.distantPast
    static let gap: TimeInterval = 0.06

    static func play(_ notes: [Chirp.Note], named key: String) {
        guard Settings.makesSounds else { return }
        guard Date().timeIntervalSince(lastAt) > gap else { return }
        lastAt = Date()
        let data: Data
        if let kept = cache[key] {
            data = kept
        } else {
            data = wav(Chirp.samples(notes))
            cache[key] = data
        }
        guard let player = try? AVAudioPlayer(data: data) else { return }
        player.volume = 0.7
        player.play()
        // Held until it has finished, or it is collected mid note and stops.
        players.append(player)
        players.removeAll { !$0.isPlaying && $0 !== player }
    }

    static func poke() { play(Chirp.poke, named: "poke") }
    static func giggle() { play(Chirp.giggle, named: "giggle") }

    /// One note per step, running through the phrase so a routine has a tune
    /// rather than a repeated beep.
    private static var step = 0
    static func danceStep() {
        let index = step % Chirp.steps.count
        step += 1
        play(Chirp.steps[index], named: "step\(index)")
    }

    static func resetDance() { step = 0 }

    /// Sixteen bit mono, which is all a chirp needs and what `AVAudioPlayer`
    /// will take straight from memory.
    private static func wav(_ samples: [Float]) -> Data {
        let rate = UInt32(Chirp.sampleRate)
        let bytes = UInt32(samples.count * 2)
        var data = Data()
        func put(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
        func put32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func put16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        put("RIFF"); put32(36 + bytes); put("WAVE")
        put("fmt "); put32(16); put16(1); put16(1)
        put32(rate); put32(rate * 2); put16(2); put16(16)
        put("data"); put32(bytes)
        for sample in samples {
            let clamped = max(-1, min(1, sample))
            put16(UInt16(bitPattern: Int16(clamped * 32_767)))
        }
        return data
    }
}
