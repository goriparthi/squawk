import AVFoundation
import AppKit
import CryptoKit
import SquawkCore

/// Something that says a line out loud. Two of them: the system's synthesiser,
/// which is always there, and a neural voice the user chose to download.
@MainActor
protocol VoiceEngine: AnyObject {
    func speak(_ text: String)
    /// Said like it means it. Only some voices can carry the difference.
    func speak(_ text: String, firmly: Bool)
    func stop()
    /// Still talking, or still working out how to.
    var isSpeaking: Bool { get }
    /// How loud it is this instant, 0 to 1, for the mouth.
    var level: Double { get }
    /// Renders a line into the cache without saying it, so the first time it
    /// is wanted is as quick as the second.
    func prepare(_ text: String)
}

@MainActor
extension VoiceEngine {
    func speak(_ text: String, firmly: Bool) { speak(text) }
    /// The system voice has nothing to prepare: it is already loaded, and it
    /// starts talking in about the time it takes to ask.
    func prepare(_ text: String) {}
}

/// `AVSpeechSynthesizer`. No download, no dependency, and it improves by itself
/// when the user installs one of the system's enhanced voices.
@MainActor
final class SystemVoice: VoiceEngine {
    /// What it normally speaks at, leaving room above for one raised voice.
    static let ordinaryVolume: Float = 0.72

    private let synthesizer = AVSpeechSynthesizer()
    private let voice: AVSpeechSynthesisVoice?

    init(identifier: String?) {
        voice = identifier.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? Self.best()
    }

    /// The best English voice installed: enhanced and premium ones are
    /// downloaded by the user in System Settings and sound far better than the
    /// compact default, so prefer them without requiring them.
    static func best() -> AVSpeechSynthesisVoice? {
        english().max { rank($0) < rank($1) }
    }

    static func english() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
    }

    private static func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
        var score = voice.quality == .premium ? 200 : (voice.quality == .enhanced ? 100 : 0)
        // A voice in the user's own region is the one they expect to hear.
        if voice.language == AVSpeechSynthesisVoice.currentLanguageCode() { score += 10 }
        return score
    }

    var isSpeaking: Bool { synthesizer.isSpeaking }

    /// `AVSpeechSynthesizer` gives no amplitude, so the jaw is driven by two
    /// rates that do not divide into each other. A single sine is a puppet.
    var level: Double {
        guard synthesizer.isSpeaking else { return 0 }
        let clock = CACurrentMediaTime()
        let wave = 0.55 + 0.30 * sin(clock * 15.3) + 0.15 * sin(clock * 6.1)
        return min(1, max(0.1, wave))
    }

    func speak(_ text: String) { speak(text, firmly: false) }

    func speak(_ text: String, firmly: Bool) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        // A shade under the default: status read at full tilt is a countdown.
        // Said firmly it slows further and drops, which is what anyone does
        // when they have stopped being asked nicely.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (firmly ? 0.82 : 0.96)
        utterance.pitchMultiplier = firmly ? 0.86 : 1
        // Full scale is full scale, so the only way to make one line louder
        // than the rest is for the rest not to be. Everything it says sits
        // below the ceiling; this is the one thing that reaches it.
        utterance.volume = firmly ? 1 : Self.ordinaryVolume
        synthesizer.speak(utterance)
    }

    func stop() {
        guard synthesizer.isSpeaking else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }
}

/// A Piper voice through the downloaded engine. One process per line, which
/// costs about a second before it starts talking, so every line it has said
/// before is kept as audio and replayed instantly.
@MainActor
final class PiperVoice: VoiceEngine {
    private let voice: VoicePack.Voice
    private var player: AVAudioPlayer?
    /// Bumped on every new line, so audio that arrives after you asked for
    /// something else is dropped rather than played over the top.
    private var generation = 0

    /// True from the moment it is asked until the audio stops, synthesis
    /// included: the engine takes about a second to load its model.
    private var working = false
    /// Whether the line being prepared is the raised one.
    private var loud = false
    var isSpeaking: Bool { working || (player?.isPlaying ?? false) }

    /// The real thing: the audio is on disk, so the jaw follows the waveform
    /// rather than an impression of one.
    var level: Double {
        guard let player, player.isPlaying else { return 0 }
        player.updateMeters()
        // Speech sits well below full scale, so the useful range is the top
        // forty decibels; mapped flat, the mouth would barely move.
        let decibels = Double(player.averagePower(forChannel: 0))
        return min(1, max(0, (decibels + 40) / 40))
    }

    init(_ voice: VoicePack.Voice) { self.voice = voice }

    func speak(_ text: String) { speak(text, firmly: false) }

    func speak(_ text: String, firmly: Bool) {
        stop()
        loud = firmly
        generation += 1
        let wanted = generation
        working = true
        let file = Self.cacheFile(for: text, voice: voice)
        if FileManager.default.fileExists(atPath: file) {
            play(file, generation: wanted)
            return
        }
        let arguments = Self.arguments(voice: voice, text: text, into: file)
        let binary = VoicePack.binary
        DispatchQueue.global(qos: .userInitiated).async {
            let made = Self.synthesise(binary: binary, arguments: arguments, into: file)
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == wanted else { return }
                working = false
                guard made else { return }
                play(file, generation: wanted)
            }
        }
    }

    /// Renders into the cache and plays nothing.
    ///
    /// Nothing is waiting on this, so it must never take the generation, set
    /// `working`, or touch the player: a warm up that made `isSpeaking` true
    /// would have the pet mouthing silence, and one that took the generation
    /// would cancel the line actually being said.
    func prepare(_ text: String) {
        let file = Self.cacheFile(for: text, voice: voice)
        guard !FileManager.default.fileExists(atPath: file) else { return }
        let arguments = Self.arguments(voice: voice, text: text, into: file)
        let binary = VoicePack.binary
        DispatchQueue.global(qos: .utility).async {
            _ = Self.synthesise(binary: binary, arguments: arguments, into: file)
        }
    }

    private static func arguments(voice: VoicePack.Voice, text: String,
                                  into file: String) -> [String] {
        [
            "--vits-model=\(VoicePack.model(voice))",
            "--vits-tokens=\(VoicePack.tokens(voice))",
            "--vits-data-dir=\(VoicePack.phonemes)",
            "--output-filename=\(file)",
            text,
        ]
    }

    func stop() {
        working = false
        player?.stop()
        player = nil
        // Anything already being synthesised is disowned, or a line told to
        // stop arrives a second later and plays over whatever came next.
        generation += 1
    }

    private func play(_ file: String, generation wanted: Int) {
        working = false
        guard generation == wanted else { return }
        player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: file))
        player?.isMeteringEnabled = true
        player?.volume = loud ? 1 : SystemVoice.ordinaryVolume
        player?.play()
    }

    /// Runs the engine to a file. Nothing reads its output, so both streams go
    /// to the null device: an unread pipe deadlocks the child once it fills.
    private nonisolated static func synthesise(
        binary: String, arguments: [String], into file: String
    ) -> Bool {
        try? FileManager.default.createDirectory(
            atPath: (file as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true, attributes: nil)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: binary)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let size = try? FileManager.default.attributesOfItem(atPath: file)[.size] as? Int,
              size > 0
        else {
            try? FileManager.default.removeItem(atPath: file)
            return false
        }
        return true
    }

    /// Keyed by the voice and the words, so changing voice does not replay the
    /// old one and the same line is only ever synthesised once.
    static func cacheFile(for text: String, voice: VoicePack.Voice) -> String {
        let key = SHA256.hash(data: Data("\(voice.id)\u{1}\(text)".utf8))
            .prefix(10).map { String(format: "%02x", $0) }.joined()
        return (VoicePack.cache as NSString).appendingPathComponent("\(key).wav")
    }
}

/// What the pet speaks with. Holds the chosen engine and rebuilds it when the
/// choice changes, so everywhere else just says what it wants said.
@MainActor
final class Speaker {
    /// A voice the user can pick: the system's, or one of the downloaded ones.
    enum Choice: Equatable {
        case system(String?)
        case piper(String)

        /// Stored in the config as one string, so an unknown or uninstalled
        /// voice falls back to the system rather than failing to load.
        var stored: String {
            switch self {
            case .system(let identifier): identifier.map { "system:\($0)" } ?? "system"
            case .piper(let id): "piper:\(id)"
            }
        }

        static func restored(_ stored: String) -> Choice {
            if stored.hasPrefix("piper:") {
                let id = String(stored.dropFirst("piper:".count))
                if let voice = VoicePack.voice(id: id), VoicePack.isReady(voice) { return .piper(id) }
                // A voice that was removed falls back like any other default.
                return preferred
            }
            if stored.hasPrefix("system:") { return .system(String(stored.dropFirst("system:".count))) }
            return preferred
        }

        /// With nothing chosen, the best voice actually installed, in catalogue
        /// order. Downloading one and still being read to by the system voice
        /// is not what anyone meant by installing it.
        static var preferred: Choice {
            VoicePack.installed.first.map { .piper($0.id) } ?? .system(nil)
        }
    }

    private var engine: VoiceEngine
    private(set) var choice: Choice

    init(choice: Choice) {
        self.choice = choice
        engine = Self.make(choice)
    }

    private static func make(_ choice: Choice) -> VoiceEngine {
        switch choice {
        case .system(let identifier):
            return SystemVoice(identifier: identifier)
        case .piper(let id):
            // A voice that was removed, or half installed, still has to talk.
            guard let voice = VoicePack.voice(id: id), VoicePack.isReady(voice) else {
                return SystemVoice(identifier: nil)
            }
            return PiperVoice(voice)
        }
    }

    func use(_ choice: Choice) {
        guard choice != self.choice else { return }
        engine.stop()
        self.choice = choice
        engine = Self.make(choice)
    }

    func say(_ text: String, firmly: Bool = false) {
        guard !text.isEmpty else { return }
        engine.speak(text, firmly: firmly)
    }

    func stop() { engine.stop() }

    /// Renders the lines it is sure to need, so the first one is not the slow
    /// one. Skips anything already cached, and never touches what is playing.
    func warm(_ lines: [String]) {
        for line in lines { engine.prepare(line) }
    }

    /// Whether a line is already rendered. For `--warm-voice`, which is the
    /// only way to see what the warm up actually costs on a given Mac.
    func isCached(_ text: String) -> Bool {
        guard case .piper(let id) = choice, let voice = VoicePack.voice(id: id) else { return true }
        return FileManager.default.fileExists(atPath: PiperVoice.cacheFile(for: text, voice: voice))
    }

    var isSpeaking: Bool { engine.isSpeaking }

    var level: Double { engine.level }

    /// What the menu shows beside the voice item.
    var title: String {
        switch choice {
        case .system(let identifier):
            let voice = identifier.flatMap(AVSpeechSynthesisVoice.init(identifier:)) ?? SystemVoice.best()
            return voice?.name ?? "System"
        case .piper(let id):
            return VoicePack.voice(id: id)?.title ?? "System"
        }
    }
}
