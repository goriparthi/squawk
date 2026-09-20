import CoreGraphics
import Foundation

/// The cards behind the one you are reading.
///
/// The ring's arcs said "three are waiting and this is the one you are looking
/// at" in a single glance, and the modelled style hides the ring, so it said
/// nothing at all: one card, no sense of a queue, and no way to reach the rest
/// but answering the one in front. A stack says the same thing in the space a
/// speech bubble already takes.
///
/// Geometry only. The bubble draws it and the roster orders it.
public enum CardStack {
    /// At most this many are drawn behind the front card. Past two the strips
    /// are thinner than the gaps between them and the whole thing reads as
    /// texture rather than as a count.
    public static let drawnDepth = 2
    /// How far each one peeks above the one in front of it.
    public static let step: CGFloat = 5
    /// And how far it is inset on each side, so the edges read as separate
    /// cards rather than as a thick border.
    public static let inset: CGFloat = 9

    /// How many are actually drawn behind the front card.
    public static func depth(waiting: Int) -> Int {
        max(0, min(waiting - 1, drawnDepth))
    }

    /// Room the peeks need above the front card, which the bubble's height
    /// constraint has to allow for or they are drawn outside the window.
    public static func headroom(waiting: Int) -> CGFloat {
        CGFloat(depth(waiting: waiting)) * step
    }

    /// Where the card at `index` behind the front one sits, and how solid it
    /// is. Index 0 is the one directly behind.
    public static func offset(behind index: Int) -> CGFloat {
        CGFloat(index + 1) * step
    }

    public static func inset(behind index: Int) -> CGFloat {
        CGFloat(index + 1) * inset
    }

    /// Fading back, so the front card is unmistakably the one being answered.
    /// Never to nothing: a card you cannot see is a card that is not saying
    /// there is anything behind.
    public static func alpha(behind index: Int) -> Double {
        max(0.18, 0.42 - Double(index) * 0.14)
    }
}
