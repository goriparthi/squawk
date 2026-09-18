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
        case failed(String)
    }

    @discardableResult
    @MainActor
    static func focus(_ request: PendingRequest) -> Outcome {
        guard let owner = owningApplication(request.ancestors ?? []) else { return .noTerminal }

        if let terminal = PaneFocus.Terminal(rawValue: owner.bundleIdentifier ?? ""),
           let source = PaneFocus.script(for: terminal, tty: request.tty, cwd: request.cwd) {
            switch run(source) {
            case .focused:
                return .focusedPane
            case .notAuthorised:
                return .failed("""
                macOS has not allowed Squawk to control \(terminal.applicationName).                 Enable it in System Settings, Privacy and Security, Automation.
                """)
            case .missed, .error:
                break
            }
        }

        // Every other terminal, and any scripted lookup that found nothing: at
        // least put the right app in front rather than doing nothing at all.
        let name = owner.localizedName ?? "the terminal"
        // A menubar app is never the active one, and since Sonoma macOS refuses
        // to let one application raise another unless the caller yields its own
        // activation first. Without this the click did nothing at all, silently.
        NSApp.yieldActivation(to: owner)
        let raised = owner.activate(from: .current, options: [.activateAllWindows])
        guard raised || owner.isActive else {
            return .failed("""
            macOS would not bring \(name) forward. If this keeps happening, allow             Squawk under System Settings, Privacy and Security, Accessibility.
            """)
        }
        return .activatedApp(name)
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

    private enum ScriptResult { case focused, missed, notAuthorised, error }

    private static func run(_ source: String) -> ScriptResult {
        guard let script = NSAppleScript(source: source) else { return .error }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int
            NSLog("squawk: focus failed: %@", error)
            // -1743 is the consent the user has not granted, which is worth
            // saying out loud rather than logging and doing nothing.
            return code == -1743 ? .notAuthorised : .error
        }
        return result.stringValue == "focused" ? .focused : .missed
    }
}
