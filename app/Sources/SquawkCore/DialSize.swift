import Foundation
import CoreGraphics

/// How big the dial sits on screen. Everything scales from the diameter so the
/// ring keeps its proportions rather than looking heavy when small and thin
/// when large.
public enum DialSize: String, CaseIterable, Sendable {
    case small
    case medium
    case large

    public static let `default` = DialSize.medium

    public var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    public var diameter: CGFloat {
        switch self {
        case .small: 288
        case .medium: 360
        case .large: 448
        }
    }

    /// The painted arc band plus its breathing room, as a share of the diameter.
    public var ringBand: CGFloat { DialGeometry.ringBand(diameter) }
    public var ringWidth: CGFloat { DialGeometry.ringWidth(diameter) }
    public var cardWidth: CGFloat { DialGeometry.cardWidth(diameter) }
    public var centreFontSize: CGFloat { DialGeometry.centreFontSize(diameter) }
    public var captionFontSize: CGFloat { DialGeometry.captionFontSize(diameter) }

    /// The preset a diameter is closest to, for ticking the right menu row when
    /// the size came from the slider.
    public static func nearest(to diameter: CGFloat) -> DialSize {
        allCases.min { abs($0.diameter - diameter) < abs($1.diameter - diameter) } ?? .default
    }

    public static func named(_ raw: String?) -> DialSize {
        guard let raw, let size = DialSize(rawValue: raw) else { return .default }
        return size
    }
}

/// Every measurement on the dial, derived from one diameter so the ring keeps
/// its proportions at any size the slider lands on. The presets are just three
/// points on this scale.
/// What the card shows at a given dial size.
public enum CardTier: Sendable {
    /// Project, tool, command, Approve and Deny, and the remembered answers.
    case full
    /// Project, tool, command, Approve and Deny.
    case compact
    /// Project, Approve and Deny. The command lives in the hover card.
    case minimal

    public var showsSecondaryActions: Bool { self == .full }
    public var showsCommand: Bool { self != .minimal }
    public var showsCount: Bool { self == .full }
}

public enum DialGeometry {
    /// A face holds the card inside its own ring, so it cannot shrink below the
    /// size of the thing it has to carry.
    public static let range: ClosedRange<CGFloat> = 150...480
    /// With a body the card moves into the speech bubble, which sizes itself, so
    /// the head carries nothing but eyes and can be far smaller.
    public static let bodyRange: ClosedRange<CGFloat> = 50...480

    public static func range(for style: PetStyle) -> ClosedRange<CGFloat> {
        style == .full ? bodyRange : range
    }

    public static func clamp(_ diameter: CGFloat, for style: PetStyle = .face) -> CGFloat {
        let limits = range(for: style)
        guard diameter.isFinite else { return DialSize.default.diameter }
        return min(max(diameter.rounded(), limits.lowerBound), limits.upperBound)
    }

    /// The card in a speech bubble is not bound by the head. The bubble is its
    /// own surface, so it stays readable however small the pet is.
    public static let bubbleCardWidth: CGFloat = 268
    /// Room the bubble leaves around the card it holds.
    public static let bubblePadding: CGFloat = 14
    /// The most text the bubble can hold. Four lines at this width, and the
    /// window is sized from the pet rather than from what it happens to be
    /// saying, so anything longer has to be cut rather than grown into.
    /// The whole answer is still spoken and still written to the week.
    public static let bubbleTextLimit = 170
    /// The bubble a full tier card needs, tail included.
    public static let bubbleFloor: CGFloat = 2 * 72 + 2 * bubblePadding + 12

    public static func bubbleWidth() -> CGFloat { bubbleCardWidth + 2 * bubblePadding }

    /// Where the card sits decides how wide it can be.
    public static func cardWidth(_ diameter: CGFloat, for style: PetStyle) -> CGFloat {
        style == .full ? bubbleCardWidth : cardWidth(diameter)
    }

    /// A card sheds rows to fit inside a ring. In a bubble it never has to, so
    /// a small pet still shows the command and the remembered answers.
    public static func tier(_ diameter: CGFloat, for style: PetStyle) -> CardTier {
        style == .full ? .full : tier(diameter)
    }

    /// The painted arc band plus its breathing room.
    public static func ringBand(_ diameter: CGFloat) -> CGFloat { (diameter * 0.094).rounded() }

    public static func ringWidth(_ diameter: CGFloat) -> CGFloat { (diameter * 0.05).rounded() }

    /// The card lives inside the inner circle, so its width is that circle's
    /// inscribed square.
    public static func cardWidth(_ diameter: CGFloat) -> CGFloat {
        ((diameter - 2 * ringBand(diameter)) / 2.squareRoot()).rounded(.down)
    }

    /// How much of the card fits inside the ring at this diameter. The card
    /// sheds rows rather than the dial having a floor at the size of its
    /// busiest state.
    public static func tier(_ diameter: CGFloat) -> CardTier {
        if diameter >= 288 { return .full }
        if diameter >= 216 { return .compact }
        return .minimal
    }

    /// Half the card's height at each tier, which is what decides whether its
    /// corners clear the ring. Kept here so the guard test and the layout agree.
    public static func cardHalfHeight(_ diameter: CGFloat) -> CGFloat {
        switch tier(diameter) {
        case .full: 72
        case .compact: 55
        case .minimal: 32
        }
    }

    /// Centre readout, the only type that scales; the card keeps fixed sizes so
    /// a command stays legible at every dial size.
    public static func centreFontSize(_ diameter: CGFloat) -> CGFloat {
        (diameter * 0.106).rounded()
    }

    public static func captionFontSize(_ diameter: CGFloat) -> CGFloat {
        max(10, (diameter * 0.034).rounded())
    }
}

/// How solid the dial sits over your work. A floating window that is always on
/// top needs to be able to recede without being dismissed.
public enum DialOpacity {
    /// Never fully transparent: a dial you cannot see is one you cannot find,
    /// and it would still be sitting there taking clicks.
    public static let range: ClosedRange<Double> = 0.25...1.0
    public static let `default` = 1.0

    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return `default` }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
