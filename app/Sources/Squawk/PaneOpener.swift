import AppKit
import SquawkCore

/// Brings an agent's real pane forward. Requires Automation permission for
/// iTerm2, which macOS prompts for on first use.
enum PaneOpener {
    @discardableResult
    static func focus(tty: String) -> Bool {
        guard let source = PaneFocus.script(forTTY: tty),
              let script = NSAppleScript(source: source)
        else { return false }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            NSLog("squawk: focus failed: %@", error)
            return false
        }
        return result.stringValue == "focused"
    }
}
