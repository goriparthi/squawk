import Foundation

/// What a click on the modelled pet meant. Decided on mouse up, like the flat
/// dial's poke, because dragging the pet somewhere is not prodding it.
public enum PetClick: Equatable, Sendable {
    case nothing
    case poke
    case dance

    /// Further than this between press and release is a drag, not a click.
    public static let dragTolerance: Double = 4

    /// The tummy is for rubbing and for the double tap that starts a dance, so
    /// a single tap there is left alone: were it a poke, the first tap of every
    /// pair would be one, and prodding the belly would start a dance. Every
    /// other part of the pet takes a poke, as many times as you like.
    public static func decide(onPet: Bool, onTummy: Bool, clicks: Int, moved: Double) -> PetClick {
        guard onPet, moved < dragTolerance else { return .nothing }
        if onTummy { return clicks == 2 ? .dance : .nothing }
        return .poke
    }
}
