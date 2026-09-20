import Foundation

/// A nudge to look up, after long enough heads down. The companion getting
/// restless is the reminder; there is no separate alert to dismiss.
public enum BreakReminder {
    /// Off by default. A tool that interrupts you uninvited has to be asked for.
    public static let defaultMinutes = 0
    /// Never nag more than this often once it has been shown.
    public static let repeatAfter: TimeInterval = 10 * 60

    /// Once it is due, how long it will hold off waiting for a gap in the work
    /// before giving up and saying it anyway.
    ///
    /// Bounded, because the point of a break reminder is the break. An agent
    /// that churns for two hours is exactly the session where somebody needs
    /// telling to look up, and a nudge that waits forever for quiet is a
    /// feature that never fires on the day it matters.
    public static let waitsForAGapFor: TimeInterval = 8 * 60

    /// Due when nothing has been answered or prodded for `minutes`, and the
    /// last nudge is far enough behind. Zero or less turns it off.
    ///
    /// `working` holds it back: a reminder landing while the agents are mid
    /// run is an interruption of the thing you are watching, and the moment
    /// the run ends is the gap it was always meant to land in. `dueSince` is
    /// when it first became due, so the hold cannot last forever.
    public static func isDue(
        minutes: Int,
        now: Date = Date(),
        lastInteraction: Date?,
        lastNudge: Date?,
        working: Bool = false,
        dueSince: Date? = nil
    ) -> Bool {
        guard minutes > 0 else { return false }
        guard let lastInteraction else { return false }
        guard now.timeIntervalSince(lastInteraction) >= Double(minutes) * 60 else { return false }
        if let lastNudge, now.timeIntervalSince(lastNudge) < repeatAfter { return false }
        guard working else { return true }
        // Held for the gap, but not indefinitely.
        guard let dueSince else { return false }
        return now.timeIntervalSince(dueSince) >= waitsForAGapFor
    }

    /// Whether it *would* be due but for the work in progress, so a caller can
    /// start the clock on how long it has been holding off.
    public static func isWaitingForAGap(
        minutes: Int,
        now: Date = Date(),
        lastInteraction: Date?,
        lastNudge: Date?
    ) -> Bool {
        guard minutes > 0, let lastInteraction else { return false }
        guard now.timeIntervalSince(lastInteraction) >= Double(minutes) * 60 else { return false }
        if let lastNudge, now.timeIntervalSince(lastNudge) < repeatAfter { return false }
        return true
    }
}

/// Sliding on and off the screen edge, for when the dial is not pinned. Arriving
/// by walking in reads as something turning up; fading in reads as a dialog.
public enum Entrance {
    public static let duration: TimeInterval = 0.42

    /// Eased position from 0 (fully offscreen) to 1 (in place).
    public static func progress(at elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }
        guard elapsed < duration else { return 1 }
        let t = elapsed / duration
        // Ease out with a small overshoot near the end, so it arrives and
        // settles rather than stopping dead. A sine wobble peaks mid travel,
        // which is not an overshoot at all.
        let back = 0.9
        let cubic = back + 1
        let p = t - 1
        let eased = 1 + cubic * pow(p, 3) + back * pow(p, 2)
        return min(max(eased, 0), 1.08)
    }

    /// How far offscreen to start, given which edge is nearest.
    public static func offset(
        for frame: CGRect,
        in visible: CGRect
    ) -> CGSize {
        let toLeft = frame.minX - visible.minX
        let toRight = visible.maxX - frame.maxX
        let toBottom = frame.minY - visible.minY
        let nearest = min(toLeft, toRight, toBottom)
        if nearest == toRight { return CGSize(width: visible.maxX - frame.minX, height: 0) }
        if nearest == toBottom { return CGSize(width: 0, height: -(frame.maxY - visible.minY)) }
        return CGSize(width: -(frame.maxX - visible.minX), height: 0)
    }
}
