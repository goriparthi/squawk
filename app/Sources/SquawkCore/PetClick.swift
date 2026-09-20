import Foundation

/// What a click on the modelled pet meant. Decided on mouse up, like the flat
/// dial's poke, because dragging the pet somewhere is not prodding it.
public enum PetClick: Equatable, Sendable {
    case nothing
    case poke
    case dance
    /// A single tap on the tummy: tickled, not prodded.
    case giggle

    /// Further than this between press and release is a drag, not a click.
    public static let dragTolerance: Double = 4

    /// The tummy giggles on a tap and dances on a double tap; a giggle never
    /// counts as a poke, so the first tap of a pair costs nothing. Every other
    /// part of the pet takes a poke, as many times as you like.
    public static func decide(onPet: Bool, onTummy: Bool, clicks: Int, moved: Double) -> PetClick {
        guard onPet, moved < dragTolerance else { return .nothing }
        if onTummy { return clicks == 2 ? .dance : (clicks == 1 ? .giggle : .nothing) }
        return .poke
    }
}

/// A deliberate "you are in my way".
///
/// From claude-pet. Dragging a pet off the thing you are reading means aiming
/// at a gap and placing it there, which is fiddly and which you then have to
/// undo. A shove is one motion that needs no aim: throw it, and it takes
/// itself away.
///
/// High effort on purpose. It has to be impossible to do by accident while
/// repositioning, or the pet would vanish every time somebody moved it.
public enum Shove: Equatable, Sendable {
    /// Points a second, past which a drag was a throw rather than a placement.
    /// Moving something deliberately tops out well below this.
    public static let speed: Double = 900
    /// And far enough that a fast twitch on the way to a click is not a shove.
    public static let distance: Double = 60
    /// How long it stays gone. Long enough to read the thing it was over,
    /// short enough that it is not really an off switch; the menu has one of
    /// those, and anything arriving brings it straight back anyway.
    public static let staysAwayFor: TimeInterval = 10 * 60

    /// Whether that drag was a shove. Both tests have to pass: far enough that
    /// it was not a twitch, and fast enough that it was not a placement.
    public static func wasShoved(distance: Double, seconds: TimeInterval) -> Bool {
        guard seconds > 0, distance >= Self.distance else { return false }
        return distance / seconds >= speed
    }
}
