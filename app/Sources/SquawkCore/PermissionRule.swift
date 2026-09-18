import Foundation

/// What a remembered answer covers. Squawk asks once and then stops asking for
/// the same shape of call, which is the only way prompting decays instead of
/// becoming something you dismiss without reading.
public struct PermissionRule: Codable, Sendable, Equatable, Hashable {
    public let tool: String
    /// The leading words of the command for Bash, empty for tools whose identity
    /// is the whole rule.
    public let prefix: String

    public init(tool: String, prefix: String) {
        self.tool = tool
        self.prefix = prefix
    }

    /// Two leading words: `git push` rather than `git`, which would wave through
    /// every git command, or the whole line, which would never match twice.
    public static func key(tool: String, summary: String) -> PermissionRule {
        guard tool == "Bash" || tool == "BashOutput" else {
            return PermissionRule(tool: tool, prefix: "")
        }
        let words = summary
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .joined(separator: " ")
        return PermissionRule(tool: tool, prefix: words)
    }

    public func matches(tool: String, summary: String) -> Bool {
        Self.key(tool: tool, summary: summary) == self
    }

    /// What the button says it will allow, so nobody grants something wider than
    /// they read.
    public var describedScope: String {
        prefix.isEmpty ? "every \(tool) call" : "\(prefix) …"
    }
}

/// Remembered answers. Session rules live and die with a session; always rules
/// are written to disk.
public struct RuleStore: Sendable {
    public private(set) var always: Set<PermissionRule>
    private var session: [String: Set<PermissionRule>]

    public init(always: Set<PermissionRule> = [], session: [String: Set<PermissionRule>] = [:]) {
        self.always = always
        self.session = session
    }

    public func allows(tool: String, summary: String, sessionId: String) -> Bool {
        let key = PermissionRule.key(tool: tool, summary: summary)
        if always.contains(key) { return true }
        return session[sessionId]?.contains(key) ?? false
    }

    public mutating func remember(tool: String, summary: String, sessionId: String, forever: Bool) {
        let key = PermissionRule.key(tool: tool, summary: summary)
        if forever {
            always.insert(key)
        } else {
            session[sessionId, default: []].insert(key)
        }
    }

    public mutating func forgetSession(_ sessionId: String) {
        session.removeValue(forKey: sessionId)
    }

    public mutating func forgetAll() {
        always.removeAll()
        session.removeAll()
    }

    public var alwaysCount: Int { always.count }
}

/// Where the always rules are kept. Same directory as the socket, same 0600,
/// because a rule is standing permission to run something.
public enum RuleFile {
    public static func path(home: String = NSHomeDirectory()) -> String {
        (SocketPath.directory(home: home) as NSString).appendingPathComponent("rules.json")
    }

    public static func load(path: String = path()) -> Set<PermissionRule> {
        guard let data = FileManager.default.contents(atPath: path),
              let rules = try? JSONDecoder().decode([PermissionRule].self, from: data)
        else { return [] }
        return Set(rules)
    }

    public static func save(_ rules: Set<PermissionRule>, path: String = path()) {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard let data = try? JSONEncoder().encode(rules.sorted {
            ($0.tool, $0.prefix) < ($1.tool, $1.prefix)
        }) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: path
        )
    }
}

/// Which permission modes Squawk steps into. Claude Code runs PreToolUse before
/// deciding whether it would even ask, so gating every mode turns silent
/// auto-approval into a dial prompt for calls that would never have stopped.
public enum GatePolicy {
    public static let defaultModes: Set<String> = ["default", "acceptEdits"]

    /// An unknown or absent mode does not gate. Over-prompting is the failure
    /// that makes this app worse than not having it, and a session that is not
    /// gated still reaches the dial through Notification.
    public static func shouldGate(mode: String?, allowed: Set<String> = defaultModes) -> Bool {
        guard let mode, !mode.isEmpty else { return false }
        return allowed.contains(mode)
    }

    /// `SQUAWK_GATE_MODES=default,auto` for anyone who wants it wider.
    public static func modes(from raw: String?) -> Set<String> {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            return defaultModes
        }
        return Set(raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty })
    }
}
