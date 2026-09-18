import Foundation
import CoreGraphics

/// A time of day to run a scheduled check.
public struct DayTime: Codable, Sendable, Equatable, Hashable, Comparable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int = 0) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public var minutesFromMidnight: Int { hour * 60 + minute }

    public static func < (lhs: DayTime, rhs: DayTime) -> Bool {
        lhs.minutesFromMidnight < rhs.minutesFromMidnight
    }

    /// `"10:00"`, which is what the config file carries.
    public var text: String { String(format: "%02d:%02d", hour, minute) }

    public init?(text: String) {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        self.init(hour: hour, minute: minute)
    }
}

/// How much of the companion is drawn.
public enum PetStyle: String, Codable, Sendable, CaseIterable {
    /// The dial alone: a face, and nothing else.
    case face
    /// Head, body and arms. Wants more room, and gestures.
    case full

    public var title: String {
        switch self {
        case .face: "Squawk Face"
        case .full: "Full Squawk"
        }
    }

    public static func named(_ raw: String?) -> PetStyle {
        guard let raw, let style = PetStyle(rawValue: raw) else { return .face }
        return style
    }
}

/// Squawk's settings, on disk and readable, rather than buried in a defaults
/// domain you need a command to inspect.
public struct SquawkConfig: Codable, Sendable, Equatable {
    /// Defaults for every field, so a config written by an older build still
    /// decodes rather than resetting everything the user had set.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = SquawkConfig()
        openAtLogin = try container.decodeIfPresent(Bool.self, forKey: .openAtLogin) ?? fallback.openAtLogin
        checkForUpdates = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? fallback.checkForUpdates
        updateCheckTimes = try container.decodeIfPresent([String].self, forKey: .updateCheckTimes) ?? fallback.updateCheckTimes
        alwaysShowDial = try container.decodeIfPresent(Bool.self, forKey: .alwaysShowDial) ?? fallback.alwaysShowDial
        dialDiameter = try container.decodeIfPresent(Double.self, forKey: .dialDiameter) ?? fallback.dialDiameter
        dialOpacity = try container.decodeIfPresent(Double.self, forKey: .dialOpacity) ?? fallback.dialOpacity
        petStyle = try container.decodeIfPresent(String.self, forKey: .petStyle) ?? fallback.petStyle
        breakReminderMinutes = try container.decodeIfPresent(Int.self, forKey: .breakReminderMinutes) ?? fallback.breakReminderMinutes
    }

    public var openAtLogin: Bool
    public var checkForUpdates: Bool
    /// When the scheduled checks run, in local time.
    public var updateCheckTimes: [String]
    public var alwaysShowDial: Bool
    public var dialDiameter: Double
    public var dialOpacity: Double
    public var petStyle: String
    /// Minutes of no interaction before it gets restless. Zero is off.
    public var breakReminderMinutes: Int

    public init(
        openAtLogin: Bool = false,
        checkForUpdates: Bool = false,
        updateCheckTimes: [String] = ["10:00", "15:00"],
        alwaysShowDial: Bool = false,
        dialDiameter: Double = 360,
        dialOpacity: Double = 1.0,
        petStyle: String = PetStyle.face.rawValue,
        breakReminderMinutes: Int = BreakReminder.defaultMinutes
    ) {
        self.openAtLogin = openAtLogin
        self.checkForUpdates = checkForUpdates
        self.updateCheckTimes = updateCheckTimes
        self.alwaysShowDial = alwaysShowDial
        self.dialDiameter = dialDiameter
        self.dialOpacity = dialOpacity
        self.petStyle = petStyle
        self.breakReminderMinutes = breakReminderMinutes
    }

    public var style: PetStyle { PetStyle.named(petStyle) }

    /// Parsed, ordered and de-duplicated. Anything unparseable is dropped rather
    /// than failing the whole file, because a hand edited config should degrade
    /// rather than reset everything.
    public var checkTimes: [DayTime] {
        let parsed = updateCheckTimes.compactMap(DayTime.init(text:))
        return Array(Set(parsed)).sorted()
    }

    /// Clamped against the style it will be drawn in: a body lets the head go
    /// far smaller than a face can, because the card is not inside it.
    public var clampedDiameter: CGFloat {
        DialGeometry.clamp(CGFloat(dialDiameter), for: style)
    }
    public var clampedOpacity: Double { DialOpacity.clamp(dialOpacity) }
}

public enum ConfigFile {
    public static func path(home: String = NSHomeDirectory()) -> String {
        (SocketPath.directory(home: home) as NSString).appendingPathComponent("config.json")
    }

    public static func load(path: String = path()) -> SquawkConfig {
        guard let data = FileManager.default.contents(atPath: path),
              let config = try? JSONDecoder().decode(SquawkConfig.self, from: data)
        else { return SquawkConfig() }
        return config
    }

    @discardableResult
    public static func save(_ config: SquawkConfig, path: String = path()) -> Bool {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return false }
        guard (try? data.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil
        else { return false }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: path
        )
        return true
    }
}
