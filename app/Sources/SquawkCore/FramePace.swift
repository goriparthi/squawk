import Foundation

/// How often the pet is drawn, decided by what it is doing rather than pinned
/// by whoever last asked for speed. Every frame costs the same whether or not
/// anything moved, so the rate is the single biggest lever on what it costs.
public enum FramePace {
    /// Standing still is a breath and a slow sway. Drawing that twice as often
    /// costs a noticeable share of a core all day and looks identical.
    public static let resting = 30
    /// A groove and a meter read fine at 30, and 60 cost half again as much
    /// (21% of a core against 14%). A track used to hold the display maximum.
    public static let listening = 30

    /// Moving (a walk, a dance) takes everything the display has; music takes
    /// enough to be smooth; standing takes the least that still breathes.
    public static func rate(moving: Bool, listening: Bool, displayMax: Int) -> Int {
        let ceiling = max(1, displayMax)
        if moving { return ceiling }
        if listening { return min(Self.listening, ceiling) }
        return min(Self.resting, ceiling)
    }
}
