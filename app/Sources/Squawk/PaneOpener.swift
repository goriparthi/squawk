import AppKit
import SquawkCore

/// Brings an agent's real pane forward. Which terminal the request came from is
/// resolved from its parent process chain, because only the terminal itself
/// knows how to be addressed. Requires Automation permission, which macOS
/// prompts for on first use.
enum PaneOpener {
    enum Outcome: Equatable {
        case focusedPane
        case activatedApp(String)
        case noTerminal
        case failed
    }

    @discardableResult
    static func focus(_ request: PendingRequest) -> Outcome {
        guard let owner = owningApplication(request.ancestors ?? []) else { return .noTerminal }

        if let terminal = PaneFocus.Terminal(rawValue: owner.bundleIdentifier ?? ""),
           let source = PaneFocus.script(for: terminal, tty: request.tty, cwd: request.cwd),
           run(source) {
            return .focusedPane
        }

        // Every other terminal, and any scripted lookup that found nothing: at
        // least put the right app in front rather than doing nothing at all.
        owner.activate(options: [])
        return .activatedApp(owner.localizedName ?? "the terminal")
    }

    /// The nearest ancestor that is a real application. Shells and the agent
    /// itself have no bundle identifier, so they fall through.
    private static func owningApplication(_ ancestors: [Int32]) -> NSRunningApplication? {
        for pid in ancestors {
            if let app = NSRunningApplication(processIdentifier: pid),
               app.bundleIdentifier != nil {
                return app
            }
        }
        return nil
    }

    private static func run(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            NSLog("squawk: focus failed: %@", error)
            return false
        }
        return result.stringValue == "focused"
    }
}
