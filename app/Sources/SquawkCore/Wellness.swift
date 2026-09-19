import Foundation

/// The things a pet can reasonably nag you about while you sit at a desk for
/// nine hours approving things an agent wants to do.
///
/// Each one is acted out rather than posted as a notification: the pet does the
/// stretch, looks away, holds up the glass. A banner is something you dismiss;
/// a small robot doing shoulder rolls at you is harder to ignore and easier to
/// forgive.
public enum WellnessPrompt: String, Sendable, CaseIterable {
    /// Twenty minutes, twenty feet, twenty seconds. The one with actual
    /// evidence behind it.
    case eyes
    case posture
    case stretch
    case water
    /// It is late and you are still here.
    case windDown

    /// How often it is worth saying, in minutes. Nil means it is not on a
    /// clock: it happens at a time of day instead.
    public var everyMinutes: Int? {
        switch self {
        case .eyes: 20
        case .posture: 35
        case .stretch: 50
        case .water: 65
        case .windDown: nil
        }
    }

    /// What it says. Short, because it is read off a robot the size of a
    /// postage stamp, and never an instruction it can check you followed.
    public var message: String {
        switch self {
        case .eyes: "Look at something far away for twenty seconds."
        case .posture: "Sit back. Shoulders down."
        case .stretch: "Stand up and stretch for a minute."
        case .water: "Get some water."
        case .windDown: "It is late. Good point to stop."
        }
    }

    /// The face it wears while asking.
    public var face: FaceExpression {
        switch self {
        case .eyes: .curious
        case .posture: .alert
        case .stretch: .restless
        case .water: .happy
        case .windDown: .sleepy
        }
    }

    /// How long it stays up. Long enough to read twice and act on.
    public var lifetime: TimeInterval { self == .windDown ? 12 : 8 }
}

/// Decides which prompt, if any, is due. Pure so the rules can be tested
/// without waiting an hour to find out.
public enum Wellness {
    /// Nothing within this of the last prompt, whatever is due. Two pieces of
    /// advice in the same minute is nagging, and nagging gets switched off.
    public static let quiet: TimeInterval = 8 * 60

    /// Before this hour nothing is due at all: a pet that starts prompting the
    /// moment you sit down has not earned the right yet.
    public static let settleIn: TimeInterval = 12 * 60

    /// The hour after which winding down is worth mentioning, local time.
    public static let lateHour = 22

    /// Away from the desk this long and the run of work is over. The clock
    /// used to measure the app's uptime, so "3h at the desk" survived a night.
    public static let awayAfter: TimeInterval = 45 * 60

    /// The same run, or a new one starting now if the last sign of life (an
    /// answer, a poke, a request arriving) is old enough to have been a break.
    public static func resumed(_ state: State, lastActive: Date, now: Date = Date()) -> State {
        guard now.timeIntervalSince(lastActive) >= awayAfter else { return state }
        return State(startedAt: now, busy: state.busy)
    }

    public struct State: Sendable {
        /// When this run of work started.
        public var startedAt: Date
        /// When each prompt last went up.
        public var lastShown: [WellnessPrompt: Date]
        /// When anything last went up, for the quiet period.
        public var lastAny: Date?
        /// Anything waiting on an answer outranks all of this.
        public var busy: Bool

        public init(startedAt: Date, lastShown: [WellnessPrompt: Date] = [:],
                    lastAny: Date? = nil, busy: Bool = false) {
            self.startedAt = startedAt
            self.lastShown = lastShown
            self.lastAny = lastAny
            self.busy = busy
        }
    }

    /// What to say now, or nothing.
    public static func due(_ state: State, now: Date = Date(),
                           calendar: Calendar = .current) -> WellnessPrompt? {
        guard !state.busy else { return nil }
        guard now.timeIntervalSince(state.startedAt) >= settleIn else { return nil }
        if let last = state.lastAny, now.timeIntervalSince(last) < quiet { return nil }

        // Winding down first: once it is late, that is the only advice worth
        // giving, and the rest of it is beside the point.
        if calendar.component(.hour, from: now) >= lateHour {
            let shown = state.lastShown[.windDown]
            // Once a night, not every eight minutes until you go to bed.
            if shown.map({ !calendar.isDate($0, inSameDayAs: now) }) ?? true {
                return .windDown
            }
            return nil
        }

        // Whichever is most overdue, so a long run does not always lead with
        // the one that happens to have the shortest interval.
        return WellnessPrompt.allCases
            .filter { $0.everyMinutes != nil }
            .compactMap { prompt -> (WellnessPrompt, Double)? in
                guard let minutes = prompt.everyMinutes else { return nil }
                let interval = Double(minutes) * 60
                let since = now.timeIntervalSince(state.lastShown[prompt] ?? state.startedAt)
                guard since >= interval else { return nil }
                return (prompt, since / interval)
            }
            .max { $0.1 < $1.1 }?.0
    }

    /// How long this run of work has been going, which is the number the wind
    /// down is really about.
    public static func atDesk(since started: Date, now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(started))
    }

    /// Readable, for the card: "3h 20m at the desk".
    public static func describe(_ elapsed: TimeInterval) -> String {
        let minutes = Int(elapsed / 60)
        guard minutes >= 60 else { return "\(max(1, minutes))m at the desk" }
        return "\(minutes / 60)h \(minutes % 60)m at the desk"
    }
}
