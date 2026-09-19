import Foundation

/// A stretch of time you have said an agent may work without stopping to ask.
///
/// Squawk already has standing permission: "Always" writes a rule to disk that
/// applies to every future session, forever, for one shape of command. This is
/// the opposite trade. It is broad but it expires, it is visible the whole time
/// it is open, and it ends by itself. For "I am watching this run, stop asking
/// me for the next ten minutes" that is a far better bargain than a permanent
/// rule granted in a hurry.
public struct RunWindow: Sendable, Equatable {
    /// Offered lengths. Nothing longer: past half an hour nobody remembers
    /// they left it open, and the whole safety of this is that it lapses.
    public static let lengths: [TimeInterval] = [5 * 60, 10 * 60, 30 * 60]

    public let until: Date
    /// What it was opened for, so the pet can say it.
    public let length: TimeInterval

    public init(length: TimeInterval, from start: Date = Date()) {
        self.length = length
        until = start.addingTimeInterval(length)
    }

    public func isOpen(at now: Date = Date()) -> Bool { now < until }

    public func remaining(at now: Date = Date()) -> TimeInterval {
        max(0, until.timeIntervalSince(now))
    }

    /// Whether this request may pass without asking.
    ///
    /// **Risk becomes load bearing here, and only here.** Everywhere else
    /// `RiskSignal` decides how the dial looks and never what is allowed, so a
    /// miss costs nothing. Inside an open window a miss means something risky
    /// runs unasked. That is the reason the window is minutes rather than
    /// hours, and the reason anything it flags still stops and waits.
    public func covers(tool: String, summary: String, at now: Date = Date()) -> Bool {
        guard isOpen(at: now) else { return false }
        return !RiskSignal.isRisky(tool: tool, summary: summary)
    }

    /// How it reads in a menu, counting down.
    public func described(at now: Date = Date()) -> String {
        let left = Int(remaining(at: now).rounded(.up))
        guard left > 0 else { return "Closed" }
        if left < 60 { return "\(left)s left" }
        return "\(Int((Double(left) / 60).rounded(.up))) min left"
    }

    public static func describe(length: TimeInterval) -> String {
        "\(Int(length / 60)) minutes"
    }
}
