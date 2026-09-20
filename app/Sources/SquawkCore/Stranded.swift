import CoreGraphics
import Foundation

/// Keeping the pet somewhere you can still reach it.
///
/// The window moves by its background, so it can be dragged clean off the side
/// of the display, and a frame saved on a display that is later unplugged comes
/// back pointing at coordinates nobody can see. Either way there is nothing
/// left to grab: the pet is running, it is answering hooks, and it is invisible.
///
/// The launch path already clamped a restored frame back inside the screen.
/// That did nothing for a drag, nothing for a display being unplugged while it
/// runs, and clamping to an edge is the wrong answer anyway: something you have
/// lost should come back to where you will find it.
public enum Stranded {
    /// How much of the pet has to be on a screen before it counts as reachable.
    /// Parking it half off an edge is a choice somebody made; losing it is not,
    /// so this is well under half rather than a demand that all of it shows.
    public static let mustShow: CGFloat = 0.4

    /// Whether too little of `frame` is on any of `screens`.
    public static func isStranded(_ frame: CGRect, on screens: [CGRect]) -> Bool {
        guard !screens.isEmpty else { return false }
        let area = frame.width * frame.height
        guard area > 0 else { return false }
        return visibleShare(frame, on: screens) < mustShow
    }

    /// The largest share of `frame` that any one screen shows. One screen, not
    /// the total: a window split across two displays is visible on both, and
    /// adding the halves would call a genuinely awkward position fine.
    public static func visibleShare(_ frame: CGRect, on screens: [CGRect]) -> CGFloat {
        let area = frame.width * frame.height
        guard area > 0 else { return 0 }
        let best = screens
            .map { $0.intersection(frame) }
            .filter { !$0.isNull && !$0.isEmpty }
            .map { $0.width * $0.height }
            .max() ?? 0
        return best / area
    }

    /// Where it should go: the middle of the screen it belongs to. The middle
    /// rather than the nearest edge, because this runs when something has gone
    /// wrong and the middle is the one place anybody will look.
    public static func home(for frame: CGRect, on screens: [CGRect]) -> CGRect? {
        guard let screen = screen(for: frame, among: screens) else { return nil }
        return CGRect(
            x: (screen.midX - frame.width / 2).rounded(),
            y: (screen.midY - frame.height / 2).rounded(),
            width: frame.width,
            height: frame.height
        )
    }

    /// The screen it overlaps most, or, when it overlaps none at all, the one
    /// whose centre is nearest. A window left on a display that has since been
    /// unplugged overlaps nothing, and that is the case this exists for.
    public static func screen(for frame: CGRect, among screens: [CGRect]) -> CGRect? {
        guard !screens.isEmpty else { return nil }
        let overlapping = screens
            .map { ($0, $0.intersection(frame)) }
            .filter { !$0.1.isNull && !$0.1.isEmpty }
            .max { ($0.1.width * $0.1.height) < ($1.1.width * $1.1.height) }
        if let overlapping { return overlapping.0 }
        return screens.min {
            distance(from: frame, to: $0) < distance(from: frame, to: $1)
        }
    }

    private static func distance(from frame: CGRect, to screen: CGRect) -> CGFloat {
        let dx = frame.midX - screen.midX
        let dy = frame.midY - screen.midY
        return dx * dx + dy * dy
    }
}
