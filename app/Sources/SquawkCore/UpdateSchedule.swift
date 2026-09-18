import Foundation

/// When the update check last ran, and whether it is due again.
///
/// The timestamp lives on disk rather than in memory so restarting Squawk does
/// not restart the clock. A laptop opened and closed all day would otherwise
/// check on every launch, which is not what "once a day" means.
public enum UpdateSchedule {
    public static var stampPath: String {
        (SocketPath.directory(home: NSHomeDirectory()) as NSString)
            .appendingPathComponent("last-update-check")
    }

    public static func lastCheck(path: String = stampPath) -> Date? {
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8),
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    public static func recordCheck(at date: Date = Date(), path: String = stampPath) {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? Data("\(date.timeIntervalSince1970)".utf8).write(to: URL(fileURLWithPath: path))
    }

    /// `hours` of zero or less turns the schedule off entirely.
    public static func isDue(every hours: Int, now: Date = Date(), lastCheck last: Date?) -> Bool {
        guard hours > 0 else { return false }
        guard let last else { return true }
        return now.timeIntervalSince(last) >= Double(hours) * 3600
    }

    public static func isDue(every hours: Int, now: Date = Date(), path: String = stampPath) -> Bool {
        isDue(every: hours, now: now, lastCheck: lastCheck(path: path))
    }

    /// The most recent scheduled moment at or before `now`, looking back into
    /// yesterday when the day's first time has not come round yet.
    public static func mostRecentOccurrence(
        of times: [DayTime],
        before now: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard !times.isEmpty else { return nil }
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now)
            else { continue }
            let candidates = times.compactMap {
                calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: day)
            }
            if let latest = candidates.filter({ $0 <= now }).max() { return latest }
        }
        return nil
    }

    /// Due when a scheduled moment has passed that the last check predates. A
    /// machine asleep at 10:00 therefore checks when it wakes, rather than
    /// skipping the slot entirely.
    public static func isDue(
        at times: [DayTime],
        now: Date = Date(),
        lastCheck last: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        guard !times.isEmpty else { return false }
        guard let due = mostRecentOccurrence(of: times, before: now, calendar: calendar)
        else { return false }
        guard let last else { return true }
        return last < due
    }
}

/// Comparison of dotted release versions, so "0.10.0" beats "0.9.0" rather than
/// losing a string comparison.
public enum Version {
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        order(candidate, current) == .orderedDescending
    }

    public static func order(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = parts(lhs)
        let right = parts(rhs)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a < b ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    /// Tolerates a leading v and any trailing suffix, because release tags carry
    /// both and neither changes which build is newer.
    static func parts(_ value: String) -> [Int] {
        value
            .trimmingCharacters(in: .whitespaces)
            .drop(while: { $0 == "v" || $0 == "V" })
            .split(separator: ".")
            .map { segment in Int(segment.prefix(while: \.isNumber)) ?? 0 }
    }
}
