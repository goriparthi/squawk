import Foundation

/// A colour as plain numbers, because the cast is described in the UI free core
/// and AppKit is not available here.
public struct Tone: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// From a hex literal, which is how the rest of the brand is written down.
    public init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }
}

/// One of the pets. The same creature in different colours rather than
/// different models: a cast you can pick from, not a wardrobe to maintain.
public struct Persona: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    /// One line, shown beside the name where it is picked.
    public let tagline: String
    /// The shell, which is most of what you see.
    public let shell: Tone
    /// Ears, antenna and the badge on its chest.
    public let accent: Tone
    /// Resting eye colour. Moods still override it: cross is orange and furious
    /// is red whoever you picked.
    public let eye: Tone

    public init(id: String, name: String, tagline: String,
                shell: Tone, accent: Tone, eye: Tone) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.shell = shell
        self.accent = accent
        self.eye = eye
    }
}

/// Everyone you can be assigned. Ordered, because this is the order they appear
/// in the menu and the order should not move under people.
public enum Cast {
    public static let all: [Persona] = [
        Persona(
            id: "pip", name: "Pip", tagline: "The original. Unbothered.",
            shell: Tone(hex: 0x2C3D46), accent: Tone(hex: 0x67E8D0), eye: Tone(hex: 0x67E8D0)
        ),
        Persona(
            id: "chalk", name: "Chalk", tagline: "Clean desk, clean conscience.",
            shell: Tone(hex: 0xEFEAE0), accent: Tone(hex: 0xE3C88B), eye: Tone(hex: 0x6FB7FF)
        ),
        Persona(
            id: "ember", name: "Ember", tagline: "Runs hot. Ships anyway.",
            shell: Tone(hex: 0x3A2622), accent: Tone(hex: 0xFF8A4C), eye: Tone(hex: 0xFFB169)
        ),
        Persona(
            id: "moss", name: "Moss", tagline: "Slow, thorough, never wrong twice.",
            shell: Tone(hex: 0x27362C), accent: Tone(hex: 0x8FD694), eye: Tone(hex: 0x9BEFA6)
        ),
        Persona(
            id: "dusk", name: "Dusk", tagline: "Works nights. Prefers it.",
            shell: Tone(hex: 0x2E2A45), accent: Tone(hex: 0xB08CFF), eye: Tone(hex: 0xC4A7FF)
        ),
        Persona(
            id: "rust", name: "Rust", tagline: "Been here longer than the repo.",
            shell: Tone(hex: 0x40312A), accent: Tone(hex: 0xD98E5A), eye: Tone(hex: 0xF0B078)
        ),
        // Very nearly black, which only works because the shell is lit rather
        // than filled: at a flat 0x000000 the whole body loses its edges and
        // reads as a hole. This is dark enough to be black and still have form.
        Persona(
            id: "soot", name: "Soot", tagline: "Says nothing. Misses nothing.",
            shell: Tone(hex: 0x14171A), accent: Tone(hex: 0x9AA6AD), eye: Tone(hex: 0xDCE6EA)
        ),
        // Named Devil, keyed ruby. The id is what a config and a groove are
        // written against, so renaming it would quietly reset anybody using it
        // back to the default pet; the name is only what you read.
        //
        // Deep enough to read as red rather than brick, and no deeper: the same
        // rule Soot lives under, that a shell this dark holds its edges only
        // because it is lit rather than filled.
        Persona(
            id: "ruby", name: "Devil", tagline: "Fast, loud, and never sorry.",
            shell: Tone(hex: 0x2B0A10), accent: Tone(hex: 0xF42234), eye: Tone(hex: 0xFF5666)
        ),
    ]

    public static let `default` = all[0]

    public static func named(_ raw: String?) -> Persona {
        guard let raw, let found = all.first(where: { $0.id == raw }) else { return `default` }
        return found
    }
}
