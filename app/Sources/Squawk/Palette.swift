import AppKit

/// The brand palette. Values come from design/squawk_design_tokens.json, which
/// is the source of truth; change them there and mirror the change here.
enum Palette {
    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    static let radarBlack = hex(0x070B0D)
    static let panel = hex(0x0C1317, alpha: 0.97)
    static let surface = hex(0x121C21)
    static let line = hex(0x26363D)
    static let primaryText = hex(0xE9F1F2)
    static let secondaryText = hex(0x8FA3AA)
    static let brand = hex(0x67E8D0)

    // State colours carry meaning, so they are named for the state not the hue.
    static let waiting = hex(0xF6B94E)
    static let waitingBright = hex(0xFFD083)
    static let running = hex(0x4FC7FF)
    static let error = hex(0xFF5B5B)
    static let complete = hex(0x5CE1A5)

    static let track = hex(0x26363D, alpha: 0.55)

    /// The dial face. Lighter than the panel token on purpose: the face has to
    /// separate from whatever is behind it, including a black desktop.
    static let faceTop = hex(0x17242B)
    static let faceBottom = hex(0x0E171C)
    static let rim = hex(0x3A4F58)
    /// The shell is lighter than the scope, which is what makes the scope read
    /// as an inset screen rather than the whole head.
    static let shellTop = hex(0x2C3D46)
    static let shellBottom = hex(0x1A262D)
    static let shellHighlight = hex(0x5C7480, alpha: 0.55)
    static let innerRim = hex(0x1D2C33)
    static let allow = complete
    static let deny = error

    /// Inter and IBM Plex Mono per the brand kit, falling back to the system
    /// faces when they are not installed rather than silently picking Helvetica.
    static func ui(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if let inter = NSFont(name: "Inter", size: size) {
            return NSFontManager.shared.convert(inter, toHaveTrait: weight >= .semibold ? .boldFontMask : [])
        }
        return .systemFont(ofSize: size, weight: weight)
    }

    static func telemetry(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont(name: "IBMPlexMono", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }
}
