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

/// What shape a character is. Two rigs, not two apps: both are driven by the
/// same `Pose3D`, so everything the pet does works on either.
public enum Build: String, Sendable, Equatable, CaseIterable {
    case biped
    case quadruped
}

/// One of the pets. Mostly the same creature in different colours, plus one
/// that walks on four legs.
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
    public let build: Build

    public init(id: String, name: String, tagline: String,
                shell: Tone, accent: Tone, eye: Tone, build: Build = .biped) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.shell = shell
        self.accent = accent
        self.eye = eye
        self.build = build
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
        Persona(
            id: "scout", name: "Scout", tagline: "Four legs. No opinions.",
            shell: Tone(hex: 0xE8B33A), accent: Tone(hex: 0x2A2A2E),
            eye: Tone(hex: 0x8FE9FF), build: .quadruped
        ),
        Persona(
            id: "bolt", name: "Bolt", tagline: "Patrols the desk. Reports back.",
            shell: Tone(hex: 0x33383F), accent: Tone(hex: 0x6FB7FF),
            eye: Tone(hex: 0x9CD8FF), build: .quadruped
        ),
    ]

    public static let `default` = all[0]

    public static func named(_ raw: String?) -> Persona {
        guard let raw, let found = all.first(where: { $0.id == raw }) else { return `default` }
        return found
    }
}
