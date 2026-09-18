import Foundation

/// Registers the PreToolUse hook in ~/.claude/settings.json. A DMG user has no
/// checkout and no Makefile, so the hook binary installs itself.
public enum HookInstaller {
    public enum Result: Equatable {
        case installed(String)
        case removed
        case failed(String)
    }

    public static func settingsPath(home: String = NSHomeDirectory()) -> String {
        ((home as NSString).appendingPathComponent(".claude") as NSString)
            .appendingPathComponent("settings.json")
    }

    /// Rewrites only Squawk's own entry, so any other hook the user configured
    /// survives. Idempotent: installing twice replaces rather than stacks.
    public static func apply(
        install: Bool,
        binary: String,
        settings path: String = settingsPath(),
        timeout: Int = 150
    ) -> Result {
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
            events.append([
                "matcher": "*",
                "hooks": [[
                    "type": "command",
                    "command": binary,
                    "timeout": timeout,
                    "statusMessage": "Waiting on Squawk",
                ]],
            ])
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

    static func isSquawk(_ entry: [String: Any]) -> Bool {
        let hooks = entry["hooks"] as? [[String: Any]] ?? []
        return hooks.contains { ($0["command"] as? String)?.contains("squawk-hook") == true }
    }
}
