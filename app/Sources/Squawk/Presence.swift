import CoreGraphics
import Foundation

/// Whether anyone is actually at the desk.
///
/// Judged by the Mac's own input, not by whether they have touched the pet: a
/// person writing code in an editor pokes nothing and answers nothing for an
/// hour, and reading that as an empty chair is what stopped the break
/// reminders from ever arriving.
enum Presence {
    /// Every kind of input worth counting. There is a wildcard event type for
    /// this, but it is a raw value with no Swift case, so the kinds are named.
    private static let kinds: [CGEventType] = [
        .mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged,
        .keyDown, .flagsChanged, .scrollWheel,
    ]

    /// Seconds since the last keystroke, click or scroll anywhere on this Mac.
    static var idleSeconds: TimeInterval {
        kinds
            .map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }
            .min() ?? 0
    }

    static var lastInput: Date { Date().addingTimeInterval(-idleSeconds) }
}
