import Foundation
import CoreGraphics

/// Recognises a tummy rub: the pointer going back and forth across the belly,
/// as opposed to passing over it on the way somewhere else. A single sweep is
/// travel; changing your mind about the direction three times is affection.
public struct TummyRub: Sendable {
    /// How far the pointer has to travel before a direction counts, so a shaky
    /// hand holding still does not rub.
    public static let threshold: CGFloat = 7
    public static let reversalsNeeded = 3
    /// The reversals have to happen close together, or a pointer that wanders
    /// over the body all afternoon would eventually add up to one.
    public static let window: TimeInterval = 1.8

    private var anchor: CGFloat?
    private var direction = 0
    private var reversals: [Date] = []

    public init() {}

    /// Feeds one pointer position. True the moment it becomes a rub, after
    /// which the count starts again so holding still does not repeat it.
    public mutating func track(x: CGFloat, at now: Date = Date()) -> Bool {
        guard let start = anchor else {
            anchor = x
            return false
        }
        let travel = x - start
        guard abs(travel) >= Self.threshold else { return false }

        let heading = travel > 0 ? 1 : -1
        anchor = x
        defer { direction = heading }
        guard direction != 0, heading != direction else { return false }

        reversals.append(now)
        reversals.removeAll { now.timeIntervalSince($0) > Self.window }
        guard reversals.count >= Self.reversalsNeeded else { return false }
        reversals.removeAll()
        return true
    }

    /// Leaving the tummy ends the rub; coming back starts a new one.
    public mutating func reset() {
        anchor = nil
        direction = 0
        reversals.removeAll()
    }
}
