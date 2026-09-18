import Foundation

/// Bringing the real pane forward, for anything you would rather read in context
/// or answer by typing. Squawk selects a pane; it never writes into one. Injecting
/// keystrokes into a TUI races the shell and lands partial lines.
public enum PaneFocus {
    /// The terminals Squawk knows how to drive, and how each one is addressed.
    public enum Terminal: String, Sendable, CaseIterable {
        case iTerm2 = "com.googlecode.iterm2"
        case appleTerminal = "com.apple.Terminal"
        case ghostty = "com.mitchellh.ghostty"

        public var applicationName: String {
            switch self {
            case .iTerm2: "iTerm2"
            case .appleTerminal: "Terminal"
            case .ghostty: "Ghostty"
            }
        }

        /// iTerm2 and Terminal expose a tty per tab, so the pane is found exactly.
        /// Ghostty's AppleScript exposes only id, name and working directory, so
        /// it is matched on the directory and can land on the wrong split when
        /// two sessions share one.
        public var matchesExactly: Bool { self != .ghostty }
    }

    /// A tty path is interpolated into an AppleScript string, so it is validated
    /// against the only shape Darwin produces rather than escaped and hoped for.
    public static func isValidTTY(_ tty: String) -> Bool {
        guard tty.hasPrefix("/dev/tty"), tty.utf8.count <= 64 else { return false }
        let suffix = tty.dropFirst("/dev/tty".count)
        guard !suffix.isEmpty else { return false }
        return suffix.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// A directory is freeform, so unlike a tty it is escaped rather than refused.
    public static func literal(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    public static func script(for terminal: Terminal, tty: String?, cwd: String) -> String? {
        switch terminal {
        case .iTerm2:
            guard let tty, isValidTTY(tty) else { return nil }
            return """
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is "\(tty)" then
                      select w
                      tell t to select
                      tell s to select
                      activate
                      return "focused"
                    end if
                  end repeat
                end repeat
              end repeat
              return "not found"
            end tell
            """

        case .appleTerminal:
            guard let tty, isValidTTY(tty) else { return nil }
            return """
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(tty)" then
                    set selected of t to true
                    set index of w to 1
                    activate
                    return "focused"
                  end if
                end repeat
              end repeat
              return "not found"
            end tell
            """

        case .ghostty:
            guard !cwd.isEmpty else { return nil }
            return """
            tell application "Ghostty"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with trm in terminals of t
                    if working directory of trm is \(literal(cwd)) then
                      focus trm
                      activate
                      return "focused"
                    end if
                  end repeat
                end repeat
              end repeat
              return "not found"
            end tell
            """
        }
    }
}
