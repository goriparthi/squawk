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

    /// The event that carries a decision. Claude Code fires PreToolUse before it
    /// has decided whether to ask, so Squawk filters by permission mode there.
    /// Codex has PermissionRequest, which fires only at the moment of asking,
    /// which is what PreToolUse on Codex would have over-prompted past.
    public var decisionEvent: String {
        switch self {
        case .claudeCode: "PreToolUse"
        case .codex: "PermissionRequest"
        }
    }

    /// Claude Code also fires Notification when it wants the human without a
    /// tool call, which is the only way a question reaches the dial. Codex has
    /// no equivalent event, so a Codex question stays in its terminal.
    public var notificationEvent: String? {
        switch self {
        case .claudeCode: "Notification"
        case .codex: nil
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

/// What an agent's config currently says about Squawk.
public enum InstallStatus: Sendable, Equatable {
    /// No Squawk entry at all.
    case missing
    /// Registered, pointing at this exact binary.
    case installed
    /// Registered, but pointing somewhere else. Moving the app between
    /// Applications folders leaves exactly this, and it looks like the hook
    /// simply not working.
    case needsUpdate(existing: String)
    /// More than one Squawk entry, which no install of ours writes.
    case conflict(count: Int)
    /// The file could not be read as JSON, so nothing may be assumed about it.
    case invalid(String)

    public var summary: String {
        switch self {
        case .missing: "not registered"
        case .installed: "registered and current"
        case .needsUpdate(let existing): "registered, but pointing at \(existing)"
        case .conflict(let count): "\(count) Squawk entries; expected one"
        case .invalid(let why): "unreadable: \(why)"
        }
    }

    public var needsAction: Bool { self != .installed }
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

    /// What the config says right now, without changing it. A stale path is the
    /// failure that looks most like the app being broken, so it is named.
    public static func status(
        binary: String,
        host: AgentHost = .claudeCode,
        settings path: String? = nil
    ) -> InstallStatus {
        let path = path ?? host.settingsPath()
        guard FileManager.default.fileExists(atPath: path) else { return .missing }
        guard let data = FileManager.default.contents(atPath: path) else {
            return .invalid("could not read \(path)")
        }
        if data.isEmpty { return .missing }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .invalid("\(path) is not valid JSON")
        }
        let hooks = root["hooks"] as? [String: Any] ?? [:]
        let entries = hooks[host.decisionEvent] as? [[String: Any]] ?? []
        let ours = entries.filter(isSquawk)
        guard !ours.isEmpty else { return .missing }
        if ours.count > 1 { return .conflict(count: ours.count) }
        let command = commandOf(ours[0]) ?? ""
        // The notify suffix is part of the command, so compare the binary only.
        let installed = command.split(separator: " ").first.map(String.init) ?? command
        return installed == binary ? .installed : .needsUpdate(existing: installed)
    }

    static func commandOf(_ entry: [String: Any]) -> String? {
        if let flat = entry["command"] as? String { return flat }
        let hooks = entry["hooks"] as? [[String: Any]] ?? []
        return hooks.compactMap { $0["command"] as? String }.first
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
            try? data.write(to: URL(fileURLWithPath: path + ".squawk-backup"), options: .atomic)
        } else {
            try? manager.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
        }

        var hooks = root["hooks"] as? [String: Any] ?? [:]

        func rewrite(_ event: String, entry: [String: Any]?) {
            var entries = hooks[event] as? [[String: Any]] ?? []
            entries.removeAll { isSquawk($0) }
            if let entry { entries.append(entry) }
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        // Older installs put Squawk on Codex's PreToolUse, which fires on every
        // call rather than at the moment of asking. Always clear that name too.
        for stale in ["PreToolUse", "PermissionRequest"] where stale != host.decisionEvent {
            rewrite(stale, entry: nil)
        }
        rewrite(host.decisionEvent,
                entry: install ? host.entry(binary: binary, timeout: timeout) : nil)
        if let event = host.notificationEvent {
            rewrite(event, entry: install
                ? host.entry(binary: binary + " --notify", timeout: 10)
                : nil)
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
            // Atomic: this is the user's agent config, and a half written file
            // loses every setting in it, not just Squawk's entry.
            try out.write(to: URL(fileURLWithPath: path), options: .atomic)
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
