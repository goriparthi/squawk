import AppKit
import ServiceManagement
import SquawkCore

// Recovery without the GUI. Open at Login can be registered against whatever
// copy was running at the time, including a build directory, and the only way
// back was a menu click in that same copy.
// Does pane focus work for the terminal I am actually in? Asks each terminal
// Squawk knows in turn, which also makes macOS raise that terminal's Automation
// consent for Squawk rather than for whatever shell ran this.
if let index = CommandLine.arguments.firstIndex(of: "--focus-tty"),
   index + 1 < CommandLine.arguments.count {
    let tty = CommandLine.arguments[index + 1]
    let cwd = FileManager.default.currentDirectoryPath
    var focused = false
    for terminal in PaneFocus.Terminal.allCases {
        guard let source = PaneFocus.script(for: terminal, tty: tty, cwd: cwd),
              let script = NSAppleScript(source: source) else {
            print("\(terminal.applicationName): no script for this input")
            continue
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int).map(String.init) ?? "?"
            print("\(terminal.applicationName): error \(code)")
            continue
        }
        let answer = result.stringValue ?? "no result"
        print("\(terminal.applicationName): \(answer)")
        if answer == "focused" { focused = true }
    }
    exit(focused ? 0 : 1)
}

if CommandLine.arguments.contains("--login-status") {
    let status = SMAppService.mainApp.status
    print("status=\(status.rawValue) enabled=\(status == .enabled)")
    exit(0)
}

if CommandLine.arguments.contains("--enable-open-at-login") {
    do {
        try SMAppService.mainApp.register()
        print("register() returned; status=\(SMAppService.mainApp.status.rawValue)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("register failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

if CommandLine.arguments.contains("--disable-open-at-login") {
    do {
        if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
        print("Open at Login is off for \(Bundle.main.bundleURL.path)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Could not unregister: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
