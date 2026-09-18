import Foundation

/// Which agent's config is being written. Both use the same PreToolUse contract
/// on the wire, so one hook binary serves both; only where it is registered and
/// the shape of that entry differ.
public enum AgentHost: String, CaseIterable, Sendable {
    case claudeCode
    case codex

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    public func settingsPath(home: String = NSHomeDirectory()) -> String {
        switch self {
        case .claudeCode:
            ((home as NSString).appendingPathComponent(".claude") as NSString)
                .appendingPathComponent("settings.json")
        case .codex:
            ((home as NSString).appendingPathComponent(".codex") as NSString)
                .appendingPathComponent("hooks.json")
        }
    }

    /// Claude Code nests handlers under a matcher; Codex takes the command flat.
    func entry(binary: String, timeout: Int) -> [String: Any] {
        switch self {
        case .claudeCode:
            [
                "matcher": "*",
                "hooks": [[
                    "type": "command",
                    "command": binary,
                    "timeout": timeout,
                    "statusMessage": "Waiting on Squawk",
                ]],
            ]
        case .codex:
            ["command": binary, "timeout": timeout]
        }
    }
}

/// Registers the PreToolUse hook in an agent's config. A DMG user has no
/// checkout and no Makefile, so the hook binary installs itself.
public enum HookInstaller {
    public enum Result: Equatable {
        case installed(String)
        case removed
        case failed(String)
    }

    public static func settingsPath(home: String = NSHomeDirectory()) -> String {
        AgentHost.claudeCode.settingsPath(home: home)
    }

    /// Rewrites only Squawk's own entry, so any other hook the user configured
    /// survives. Idempotent: installing twice replaces rather than stacks.
    public static func apply(
        install: Bool,
        binary: String,
        host: AgentHost = .claudeCode,
        settings path: String? = nil,
        timeout: Int = 150
    ) -> Result {
        let path = path ?? host.settingsPath()
        let manager = FileManager.default
        var root: [String: Any] = [:]

        if manager.fileExists(atPath: path) {
            guard let data = manager.contents(atPath: path) else {
                return .failed("Could not read \(path)")
            }
            if !data.isEmpty {
                guard let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return .failed("\(path) is not valid JSON; leaving it alone") }
                root = parsed
            }
            // A backup before touching the file that governs every session.
            try? data.write(to: URL(fileURLWithPath: path + ".squawk-backup"))
        } else {
            try? manager.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var events = hooks["PreToolUse"] as? [[String: Any]] ?? []
        events.removeAll { isSquawk($0) }

        if install {
            events.append(host.entry(binary: binary, timeout: timeout))
        }

        if events.isEmpty {
            hooks.removeValue(forKey: "PreToolUse")
        } else {
            hooks["PreToolUse"] = events
        }
        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }

        guard let out = try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return .failed("Could not serialise settings") }

        do {
            try out.write(to: URL(fileURLWithPath: path))
        } catch {
            return .failed("Could not write \(path): \(error.localizedDescription)")
        }
        return install ? .installed(binary) : .removed
    }

    /// Matches both shapes, so an entry written for either agent is recognised
    /// and a reinstall replaces it rather than stacking a second one.
    public static func isSquawk(_ entry: [String: Any]) -> Bool {
        if let flat = entry["command"] as? String, flat.contains("squawk-hook") { return true }
        let hooks = entry["hooks"] as? [[String: Any]] ?? []
        return hooks.contains { ($0["command"] as? String)?.contains("squawk-hook") == true }
    }
}
