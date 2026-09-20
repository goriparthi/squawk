import Foundation
import CoreGraphics

/// How big the pet sits on screen. Three points on the slider's scale, so the
/// menu can offer sizes without anybody typing a number.
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

/// Every measurement the window is built from, derived from the one size the
/// user sets.
public enum DialGeometry {
    /// The card lives in the speech bubble, which sizes itself, so the head
    /// carries nothing but eyes and can go small. There used to be a second,
    /// higher floor, for the style that kept the card inside its own ring.
    public static let range: ClosedRange<CGFloat> = 50...480

    public static func clamp(_ diameter: CGFloat) -> CGFloat {
        guard diameter.isFinite else { return DialSize.default.diameter }
        return min(max(diameter.rounded(), range.lowerBound), range.upperBound)
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
    /// The bubble a card needs, tail included.
    public static let bubbleFloor: CGFloat = 2 * 72 + 2 * bubblePadding + 12

    public static func bubbleWidth() -> CGFloat { bubbleCardWidth + 2 * bubblePadding }
}

/// How solid the pet sits over your work. A floating window that is always on
/// top needs to be able to recede without being dismissed.
public enum DialOpacity {
    /// Never fully transparent: one you cannot see is one you cannot find, and
    /// it would still be sitting there taking clicks.
    public static let range: ClosedRange<Double> = 0.25...1.0
    public static let `default` = 1.0

    public static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return `default` }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
