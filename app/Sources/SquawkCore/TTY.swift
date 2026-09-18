import Foundation

/// Which terminal a hook was spawned under. The hook inherits the agent's
/// controlling terminal, which is what ties a request back to a visible pane.
public enum TTY {
    /// stdin is a pipe when Claude Code feeds the hook its JSON, so the terminal
    /// is found on stderr first and through the controlling terminal after that.
    public static func current(
        ttynameFor: (Int32) -> String? = { fd in
            guard let raw = ttyname(fd) else { return nil }
            return String(cString: raw)
        },
        controllingTerminal: () -> String? = TTY.viaControllingTerminal
    ) -> String? {
        for fd in [STDERR_FILENO, STDOUT_FILENO, STDIN_FILENO] {
            if let name = ttynameFor(fd), PaneFocus.isValidTTY(name) {
                return name
            }
        }
        if let name = controllingTerminal(), PaneFocus.isValidTTY(name) {
            return name
        }
        // Last and most reliable: the process table, walking up to the agent.
        if let name = ProcessTree.nearestTTY(), PaneFocus.isValidTTY(name) {
            return name
        }
        return nil
    }

    public static func viaControllingTerminal() -> String? {
        let fd = open("/dev/tty", O_RDONLY | O_NOCTTY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard let raw = ttyname(fd) else { return nil }
        return String(cString: raw)
    }
}
