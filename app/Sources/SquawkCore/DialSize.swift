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
        case .small: 248
        case .medium: 320
        case .large: 396
        }
    }

    /// The painted arc band plus its breathing room, as a share of the diameter.
    public var ringBand: CGFloat { (diameter * 0.094).rounded() }

    public var ringWidth: CGFloat { (diameter * 0.05).rounded() }

    /// The card lives inside the inner circle, so its width is that circle's
    /// inscribed square.
    public var cardWidth: CGFloat {
        ((diameter - 2 * ringBand) / 2.squareRoot()).rounded(.down)
    }

    /// Centre readout, which is the only type that scales; the card keeps fixed
    /// sizes so a command stays legible at every dial size.
    public var centreFontSize: CGFloat { (diameter * 0.106).rounded() }
    public var captionFontSize: CGFloat { max(10, (diameter * 0.034).rounded()) }

    public static func named(_ raw: String?) -> DialSize {
        guard let raw, let size = DialSize(rawValue: raw) else { return .default }
        return size
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
