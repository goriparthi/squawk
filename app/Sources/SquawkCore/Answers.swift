import Foundation

/// Questions the pet can answer exactly, without asking anything or anyone.
///
/// The clock is the clearest case: a language model will state today's date
/// with complete confidence and be wrong, because it cannot know it. Anything
/// with a right answer available on the machine is computed, never generated.
public enum Answers {
    /// An exact answer, or nil when this is not a question of that kind.
    public static func exact(for question: String, now: Date = Date(),
                             calendar: Calendar = .current,
                             timeZone: TimeZone = .current) -> String? {
        let asked = Listening.normalise(question)
        guard !asked.isEmpty else { return nil }
        var calendar = calendar
        calendar.timeZone = timeZone

        if mentions(asked, ["time", "o'clock", "oclock"]) {
            return "It's \(spokenTime(now, calendar: calendar))."
        }
        if mentions(asked, ["day of the week", "what day", "which day", "day is it", "today"]) {
            return "It's \(name(of: now, format: "EEEE", timeZone: timeZone)), \(spokenDate(now, timeZone: timeZone))."
        }
        if mentions(asked, ["date", "what's the date", "month", "year"]) {
            return "It's \(spokenDate(now, timeZone: timeZone))."
        }
        return nil
    }

    /// Whether this is a question about the weather, which needs the network
    /// and a place, so it is answered elsewhere.
    public static func isAboutWeather(_ question: String) -> Bool {
        mentions(Listening.normalise(question),
                 ["weather", "temperature", "forecast", "how hot", "how cold", "how warm",
                  "raining", "rain", "snowing", "snow", "sunny", "windy", "outside"])
    }

    /// Whether this is worth sending anywhere at all. Two words near a pet is
    /// someone talking to someone else; a question is a sentence.
    public static func isWorthAnswering(_ question: String) -> Bool {
        Listening.normalise(question).split(separator: " ").count >= 3
    }

    /// Spoken, not printed: "quarter past four", not "16:15". A clock read out
    /// as digits is a departure board.
    static func spokenTime(_ now: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        let part = hour < 12 ? "in the morning" : (hour < 18 ? "in the afternoon" : "in the evening")
        switch minute {
        case 0: return "\(twelve) o'clock \(part)"
        case 15: return "quarter past \(twelve) \(part)"
        case 30: return "half past \(twelve) \(part)"
        case 45:
            let next = (twelve % 12) + 1
            return "quarter to \(next)"
        default:
            let minutes = minute < 10 ? "oh \(minute)" : "\(minute)"
            return "\(twelve) \(minutes) \(part)"
        }
    }

    static func spokenDate(_ now: Date, timeZone: TimeZone) -> String {
        let month = name(of: now, format: "MMMM", timeZone: timeZone)
        let day = name(of: now, format: "d", timeZone: timeZone)
        let year = name(of: now, format: "yyyy", timeZone: timeZone)
        return "\(month) the \(ordinal(day)), \(year)"
    }

    private static func name(of date: Date, format: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    static func ordinal(_ day: String) -> String {
        guard let number = Int(day) else { return day }
        switch number {
        case 11, 12, 13: return "\(number)th"
        default:
            switch number % 10 {
            case 1: return "\(number)st"
            case 2: return "\(number)nd"
            case 3: return "\(number)rd"
            default: return "\(number)th"
            }
        }
    }

    private static func mentions(_ asked: String, _ phrases: [String]) -> Bool {
        phrases.contains { asked == $0 || asked.contains($0) }
    }
}
