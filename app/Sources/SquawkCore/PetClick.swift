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
