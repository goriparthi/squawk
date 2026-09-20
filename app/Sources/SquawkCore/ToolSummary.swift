import Foundation

/// Turns a tool call into the one line shown on the ring. Seeing `rm -rf build`
/// rather than `Bash` is the whole point of deciding without opening the pane.
public enum ToolSummary {
    public static let maxLength = 120

    public static func describe(tool: String, input: [String: JSONValue]?, cwd: String) -> String {
        guard let input else { return tool }

        let raw: String? = switch tool {
        case "Bash", "BashOutput":
            input["command"]?.stringValue
        case "Read", "Write", "NotebookEdit":
            input["file_path"]?.stringValue.map { relativize($0, to: cwd) }
        case "Edit":
            input["file_path"]?.stringValue.map { relativize($0, to: cwd) }
        case "Glob", "Grep":
            input["pattern"]?.stringValue
        case "WebFetch":
            input["url"]?.stringValue
        case "WebSearch":
            input["query"]?.stringValue
        case "Task", "Agent":
            input["description"]?.stringValue
        default:
            input["description"]?.stringValue ?? input["command"]?.stringValue
        }

        guard let raw, !raw.isEmpty else { return tool }
        return sanitize(redact(raw))
    }

    /// Paths inside the session's own directory are shown relative, because the
    /// home prefix is identical on every row and crowds out the part that differs.
    public static func relativize(_ path: String, to cwd: String) -> String {
        guard !cwd.isEmpty else { return path }
        let base = cwd.hasSuffix("/") ? cwd : cwd + "/"
        if path.hasPrefix(base) {
            return String(path.dropFirst(base.count))
        }
        let home = NSHomeDirectory()
        if !home.isEmpty, path.hasPrefix(home + "/") {
            return "~/" + path.dropFirst(home.count + 1)
        }
        return path
    }

    /// Masks things that look like credentials before the command is ever
    /// drawn. The dial sits on screen during screen shares and screenshots, and
    /// a token in an approval prompt is a token you have published.
    ///
    /// Crude on purpose, and never a reason to relax anything else: it changes
    /// what is displayed, not what is approved.
    public static func redact(_ text: String) -> String {
        var result = text

        // Flag-carried secrets: --password=x, --token x, -p hunter2.
        let flagged = #"(?i)(--?(?:password|passwd|pwd|token|secret|api[-_]?key|auth)[ =:]+)(\S+)"#
        result = result.replacingOccurrences(
            of: flagged, with: "$1••••", options: .regularExpression
        )

        // Header-carried secrets: Authorization: Bearer xyz.
        result = result.replacingOccurrences(
            of: #"(?i)(authorization:\s*\w+\s+)(\S+)"#,
            with: "$1••••", options: .regularExpression
        )

        // Vendor prefixed keys, which are unmistakable and worth catching whole.
        for pattern in [#"\bgh[pousr]_[A-Za-z0-9]{16,}"#,
                        #"\bsk-[A-Za-z0-9_-]{16,}"#,
                        #"\bxox[baprs]-[A-Za-z0-9-]{10,}"#,
                        #"\bAKIA[0-9A-Z]{16}\b"#,
                        #"\bAIza[0-9A-Za-z_-]{30,}"#] {
            result = result.replacingOccurrences(
                of: pattern, with: "••••", options: .regularExpression
            )
        }
        return result
    }

    /// Control characters would break the panel's layout, and an escape sequence
    /// in a command is exactly the thing an attacker would use to hide it.
    ///
    /// The limit is a parameter because a spoken line gets more room than a
    /// command on the ring: the ring has a circle to fit inside and this has not.
    public static func sanitize(_ text: String, to limit: Int = maxLength) -> String {
        let collapsed = text.unicodeScalars
            .map { scalar -> Character in
                if scalar.properties.generalCategory == .control || scalar == "\u{7F}" {
                    return " "
                }
                return Character(scalar)
            }
            .reduce(into: "") { partial, character in
                if character == " ", partial.last == " " { return }
                partial.append(character)
            }
            .trimmingCharacters(in: .whitespaces)

        return truncate(collapsed, to: limit)
    }

    public static func truncate(_ text: String, to limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "\u{2026}"
    }
}
