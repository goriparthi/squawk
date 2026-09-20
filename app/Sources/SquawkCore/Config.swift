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
        character = try container.decodeIfPresent(String.self, forKey: .character)
            ?? Cast.default.id
        reactsToAudio = try container.decodeIfPresent(Bool.self, forKey: .reactsToAudio) ?? false
        wellness = try container.decodeIfPresent(Bool.self, forKey: .wellness) ?? false
        breakReminderMinutes = try container.decodeIfPresent(Int.self, forKey: .breakReminderMinutes) ?? fallback.breakReminderMinutes
        bubbleBelow = try container.decodeIfPresent(Bool.self, forKey: .bubbleBelow) ?? false
        speaksAloud = try container.decodeIfPresent(Bool.self, forKey: .speaksAloud) ?? false
        voiceId = try container.decodeIfPresent(String.self, forKey: .voiceId) ?? ""
        phrasesWithModel = try container.decodeIfPresent(Bool.self, forKey: .phrasesWithModel) ?? false
        phrasingModel = try container.decodeIfPresent(String.self, forKey: .phrasingModel) ?? ""
        listensForWakeWord = try container.decodeIfPresent(Bool.self, forKey: .listensForWakeWord) ?? false
        pushToTalk = try container.decodeIfPresent(Bool.self, forKey: .pushToTalk) ?? false
        logsListening = try container.decodeIfPresent(Bool.self, forKey: .logsListening) ?? true
        answersQuestions = try container.decodeIfPresent(Bool.self, forKey: .answersQuestions) ?? false
        weatherPlace = try container.decodeIfPresent(String.self, forKey: .weatherPlace) ?? ""
        lastGreeting = try container.decodeIfPresent(String.self, forKey: .lastGreeting) ?? ""
        makesSounds = try container.decodeIfPresent(Bool.self, forKey: .makesSounds) ?? true
        agentsMaySpeak = try container.decodeIfPresent(Bool.self, forKey: .agentsMaySpeak) ?? false
    }

    public var openAtLogin: Bool
    public var checkForUpdates: Bool
    /// When the scheduled checks run, in local time.
    public var updateCheckTimes: [String]
    public var alwaysShowDial: Bool
    public var dialDiameter: Double
    public var dialOpacity: Double
    /// Which of the cast is on screen.
    public var character: String = Cast.default.id
    /// Whether it listens to what the machine is playing. Off until asked.
    public var reactsToAudio: Bool = false
    /// Whether it looks after you as well as your agents. Off until asked.
    public var wellness: Bool = false
    /// Minutes of no interaction before it gets restless. Zero is off.
    public var breakReminderMinutes: Int
    /// Whether the bubble was under the pet when the frame was saved. The frame
    /// alone restored into the other layout and the pet jumped on relaunch.
    public var bubbleBelow: Bool = false
    /// Whether it says out loud what the agents are doing. Off until asked.
    public var speaksAloud: Bool = false
    /// Which voice, as `Speaker.Choice` stores it. Empty is the system's own.
    public var voiceId: String = ""
    /// Whether a model on this machine rephrases what it says. Off until asked.
    public var phrasesWithModel: Bool = false
    /// Which Ollama model does it. Empty picks the best installed one.
    public var phrasingModel: String = ""
    /// Whether the microphone stays open for its name. Off until asked.
    public var listensForWakeWord: Bool = false
    /// Whether the hotkey records while held. Off until asked.
    public var pushToTalk: Bool = false
    /// Whether it keeps a local record of what it heard, for working out why a
    /// command went nowhere. On, because a voice that does nothing is
    /// otherwise impossible to diagnose, and off in one click.
    public var logsListening: Bool = true
    /// Whether it answers questions of its own, rather than only about your
    /// agents. Off until asked: it is a different job.
    public var answersQuestions: Bool = false
    /// Where the weather is. Empty takes the city out of the Mac's time zone.
    public var weatherPlace: String = ""
    /// What it said last time it started, so it says something else this time.
    public var lastGreeting: String = ""
    /// Whether it chirps when prodded and while it dances. Never over music.
    public var makesSounds: Bool = true

    /// Whether an agent may say a line through the pet, using the MCP speak
    /// tool. Off until asked: it lets whatever is driving the agent choose
    /// words that come out of your speakers.
    public var agentsMaySpeak: Bool = false

    public init(
        openAtLogin: Bool = false,
        checkForUpdates: Bool = false,
        updateCheckTimes: [String] = ["10:00", "15:00"],
        alwaysShowDial: Bool = false,
        dialDiameter: Double = 360,
        dialOpacity: Double = 1.0,
        breakReminderMinutes: Int = BreakReminder.defaultMinutes
    ) {
        self.openAtLogin = openAtLogin
        self.checkForUpdates = checkForUpdates
        self.updateCheckTimes = updateCheckTimes
        self.alwaysShowDial = alwaysShowDial
        self.dialDiameter = dialDiameter
        self.dialOpacity = dialOpacity
        self.breakReminderMinutes = breakReminderMinutes
    }

    public var persona: Persona { Cast.named(character) }

    /// Parsed, ordered and de-duplicated. Anything unparseable is dropped rather
    /// than failing the whole file, because a hand edited config should degrade
    /// rather than reset everything.
    public var checkTimes: [DayTime] {
        let parsed = updateCheckTimes.compactMap(DayTime.init(text:))
        return Array(Set(parsed)).sorted()
    }

    public var clampedDiameter: CGFloat {
        DialGeometry.clamp(CGFloat(dialDiameter))
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
