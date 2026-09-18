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
        return sanitize(raw)
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

    /// Control characters would break the panel's layout, and an escape sequence
    /// in a command is exactly the thing an attacker would use to hide it.
    public static func sanitize(_ text: String) -> String {
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

        return truncate(collapsed, to: maxLength)
    }

    public static func truncate(_ text: String, to limit: Int) -> String {
        guard limit > 0 else { return "" }
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "\u{2026}"
    }
}
