import Foundation

/// Bringing the real pane forward, for anything you would rather read in context
/// or answer by typing. Squawk selects a pane; it never writes into one. Injecting
/// keystrokes into a TUI races the shell and lands partial lines.
public enum PaneFocus {
    /// A tty path is interpolated into an AppleScript string, so it is validated
    /// against the only shape Darwin produces rather than escaped and hoped for.
    public static func isValidTTY(_ tty: String) -> Bool {
        guard tty.hasPrefix("/dev/tty"), tty.utf8.count <= 64 else { return false }
        let suffix = tty.dropFirst("/dev/tty".count)
        guard !suffix.isEmpty else { return false }
        return suffix.allSatisfy { $0.isLetter || $0.isNumber }
    }

    /// Walks every window, tab and session because iTerm2 exposes `tty` per
    /// session and offers no lookup by it.
    public static func script(forTTY tty: String) -> String? {
        guard isValidTTY(tty) else { return nil }
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
    }
}
