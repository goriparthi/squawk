import Foundation

/// Whether the agents are actually churning right now.
///
/// The pet used to drift to bored and then to sleepy whenever nothing was
/// *waiting*, which on an auto approved session is the whole time: the machine
/// hammers through tool calls for twenty minutes and the pet sleeps through it.
/// Arrivals are the better signal, and Squawk already keeps them.
///
/// Two thresholds and a confirmation, because the naive version flickers. One
/// burst of three calls must not set it working, and one pause between a build
/// and its tests must not stop it.
public struct WorkPace: Sendable, Equatable {
    /// Arrivals inside the window that mean work is happening.
    public static let busyAbove = 3
    /// ...and what it has to fall back to before it is over. The gap between
    /// the two is the hysteresis: at a single threshold a session sitting on
    /// the line turns the pet on and off every sample.
    public static let quietBelow = 1
    /// How far back an arrival still counts. Long enough to span a compile.
    public static let window: TimeInterval = 90
    /// Samples that have to agree before the state actually changes. The pet
    /// leans in a little sooner than it settles back, because noticing late
    /// looks broken and settling late just looks patient.
    public static let toStart = 2
    public static let toStop = 4

    public private(set) var isWorking = false
    /// Consecutive samples pointing the other way.
    private var disagreeing = 0

    public init(isWorking: Bool = false) {
        self.isWorking = isWorking
    }

    /// One sample. Returns whether the state changed, so a caller can avoid
    /// redrawing for a reading that said the same thing as the last one.
    @discardableResult
    public mutating func sample(arrivals: Int) -> Bool {
        // Between the two thresholds nothing is decided either way, and the
        // run of disagreement is left alone rather than reset: a session
        // hovering on the line would otherwise never resolve.
        let wants: Bool?
        if arrivals >= Self.busyAbove {
            wants = true
        } else if arrivals <= Self.quietBelow {
            wants = false
        } else {
            wants = nil
        }

        guard let wants else { return false }
        guard wants != isWorking else {
            disagreeing = 0
            return false
        }
        disagreeing += 1
        guard disagreeing >= (wants ? Self.toStart : Self.toStop) else { return false }
        isWorking = wants
        disagreeing = 0
        return true
    }
}

extension Journal {
    /// Tool calls that arrived inside the window ending now.
    ///
    /// Arrivals rather than approvals, because an auto approved call never
    /// reaches a decision, and that traffic is exactly what used to leave the
    /// pet asleep while the machine was busy.
    public func arrivals(within window: TimeInterval = WorkPace.window,
                         now: Date = Date()) -> Int {
        let cutoff = now.addingTimeInterval(-window)
        return entries.lazy.filter { $0.at >= cutoff && $0.kind == .arrived }.count
    }
}
