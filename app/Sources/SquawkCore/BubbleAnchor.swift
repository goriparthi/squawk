import CoreGraphics

/// Where the speech bubble sits when the pet is parked near the edge of a
/// display. The bubble is wider than the pet, so a pet in the corner had half
/// its card off the screen.
///
/// The bubble slides and the tail slides the other way, so it still points at
/// the head. Moving the pet instead would mean the window walking away from
/// wherever it was put, which is worse than a card that leans.
public enum BubbleAnchor {
    /// Clear of the edge by this much, so it never looks welded to it.
    public static let margin: CGFloat = 8

    /// How far to slide the bubble sideways, in points. Positive is right.
    /// - Parameters:
    ///   - centre: the pet's centre in screen coordinates.
    ///   - width: the bubble's full width.
    ///   - visible: the usable part of the display it is on.
    public static func shift(centre: CGFloat, width: CGFloat, visible: CGRect) -> CGFloat {
        let half = width / 2
        var shift: CGFloat = 0
        if centre - half < visible.minX + margin {
            shift = (visible.minX + margin) - (centre - half)
        } else if centre + half > visible.maxX - margin {
            shift = (visible.maxX - margin) - (centre + half)
        }
        // Past this the tail runs out of bubble to point from, and a tail
        // hanging off the corner is worse than a card that overhangs slightly.
        let limit = max(0, half - tailRoom)
        return min(max(shift, -limit), limit)
    }

    /// Room the tail needs inside the bubble's rounded end: its own half width
    /// plus the corner radius, or it ends up pointing out of the curve.
    public static let tailRoom: CGFloat = 24

    /// How far the pet's centre has to be from the edge for the whole bubble to
    /// fit beside it. Closer than this and the tail would have to sit outside
    /// the bubble's rounded end, so the card is allowed to overhang instead:
    /// a pet parked that far into the corner is half off the display itself.
    public static func clearanceNeeded(width: CGFloat) -> CGFloat {
        margin + tailRoom + 1
    }

    /// Whether the bubble has to go under the pet instead of over it. Over is
    /// the normal case; under is for a pet parked against the top of the
    /// screen, where a bubble above would be off the display and the pet, not
    /// the bubble, is the thing the person put where it is.
    ///
    /// Sticky: it goes under when the room above runs out, and only comes back
    /// over once there is the whole bubble's worth of room again, so dragging
    /// along the top edge does not flip it back and forth.
    public static func shouldSitBelow(
        panelTop: CGFloat, bubbleHeight: CGFloat, visibleTop: CGFloat,
        currentlyBelow: Bool
    ) -> Bool {
        // With the bubble above, the panel's top is the bubble's top. With it
        // below, the panel's top is the pet's top, and the bubble would need
        // the whole of its height above that to go back.
        if currentlyBelow {
            return panelTop + bubbleHeight > visibleTop - margin
        }
        return panelTop > visibleTop + 2
    }
}
