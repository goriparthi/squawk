import Foundation

/// Whether now is a good moment to say something nobody asked for.
///
/// From Live2DPet. A pet that speaks the instant it has a line interrupts
/// whatever you were in the middle of; the same line, once you have settled
/// somewhere, is a remark. Nothing here applies to answers, refusals or
/// anything waiting on you: those were asked for, or they are the job.
public struct Dwell: Sendable, Equatable {
    /// How long one context has to hold before anything is volunteered.
    /// Long enough to be past a burst of window switching, short enough that
    /// settling down to read is not a wait.
    public static let settles: TimeInterval = 12

    /// What is in front of you, and since when.
    private var context: String?
    private var since: Date?

    public init() {}

    /// Notes what is frontmost. Same context, same clock: only a change
    /// restarts it, or, fed on a timer, nobody would ever settle at all.
    ///
    /// The first ask always starts the clock, even for nothing frontmost.
    /// Treating "no change from nil" as no news meant that with no application
    /// focused at launch the pet never settled and never said hello.
    public mutating func entered(_ context: String?, at now: Date = Date()) {
        guard since == nil || context != self.context else { return }
        self.context = context
        since = now
    }

    /// How long the current context has held.
    public func settledFor(at now: Date = Date()) -> TimeInterval {
        guard let since else { return 0 }
        return max(0, now.timeIntervalSince(since))
    }

    /// Whether something unasked for may be said.
    public func mayVolunteer(at now: Date = Date()) -> Bool {
        settledFor(at: now) >= Self.settles
    }
}

/// How far apart ambient behaviour should be, given how long nothing has
/// changed.
///
/// Also from Live2DPet, and the half that is easy to miss: a pet that fidgets
/// at the same rate after an hour of nothing is a pet you have stopped seeing.
/// Slowing down is what makes the next one land.
public enum Ambient {
    /// Nothing has changed for this long, so the pace is at its slowest.
    public static let fullyQuietAfter: TimeInterval = 45 * 60
    /// How much further apart moves get by then.
    public static let slowestFactor: Double = 3.0

    /// The gap to use, given the base gap and how long it has been quiet.
    /// Eased rather than stepped, so there is no moment where the pet visibly
    /// changes gear.
    public static func gap(base: TimeInterval, quietFor: TimeInterval) -> TimeInterval {
        guard quietFor > 0 else { return base }
        let share = min(1, quietFor / fullyQuietAfter)
        // Squared, so the first few minutes barely slow at all and the long
        // tail does most of the stretching.
        return base * (1 + (slowestFactor - 1) * share * share)
    }
}
