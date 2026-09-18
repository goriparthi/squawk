import AppKit
import SquawkCore

/// Undoing everything Squawk put on the machine. The hook comes first: it is the
/// only piece that affects sessions Squawk is not part of, so it must come out
/// even if the rest fails.
@MainActor
enum Uninstaller {
    struct Report {
        var removedHook = false
        var hookMessage: String?
        var removedLoginItem = false
        var removedSupportFiles = false
    }

    /// Everything except the bundle itself, which cannot be removed by the
    /// process running from it.
    static func removeTraces() -> Report {
        var report = Report()

        let hookBinary = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/squawk-hook").path
        // Whichever agents it was registered with; a config that is absent is
        // simply left alone by the installer.
        for host in AgentHost.allCases {
            guard FileManager.default.fileExists(atPath: host.settingsPath()) else { continue }
            switch HookInstaller.apply(install: false, binary: hookBinary, host: host) {
            case .removed, .installed:
                report.removedHook = true
            case .failed(let message):
                report.hookMessage = "\(host.displayName): \(message)"
            }
        }

        if LoginItem.isEnabled {
            report.removedLoginItem = LoginItem.set(false) == nil
        }

        let support = SocketPath.directory(home: NSHomeDirectory())
        if FileManager.default.fileExists(atPath: support) {
            report.removedSupportFiles =
                (try? FileManager.default.removeItem(atPath: support)) != nil
        }

        UserDefaults.standard.removeObject(forKey: "checkForUpdatesDaily")
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame SquawkDial")

        return report
    }

    /// Hands the bundle to a detached helper that waits for this process to exit.
    /// It moves the app to the Trash rather than deleting it, so an uninstall
    /// someone regrets is one Put Back away.
    static func trashBundleAfterQuit() -> String? {
        let bundle = Bundle.main.bundleURL
        guard bundle.pathExtension == "app" else { return nil }

        let manager = FileManager.default
        let work = manager.temporaryDirectory
            .appendingPathComponent("squawk-uninstall-\(UUID().uuidString)")
        guard (try? manager.createDirectory(at: work, withIntermediateDirectories: true)) != nil
        else { return "Could not prepare the uninstall helper." }

        let script = work.appendingPathComponent("uninstall.sh")
        // mv rather than asking Finder: controlling Finder needs Automation
        // consent, and that prompt would arrive after Squawk has already quit.
        let body = """
        #!/bin/bash
        PID=$1; WORK=$2; TARGET=$3
        for _ in $(seq 1 150); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
        if [ -e "$TARGET" ]; then
            mkdir -p "$HOME/.Trash"
            DEST="$HOME/.Trash/$(basename "$TARGET")"
            [ -e "$DEST" ] && DEST="$HOME/.Trash/Squawk $(date +%Y-%m-%d-%H%M%S).app"
            mv "$TARGET" "$DEST"
        fi
        rm -rf "$WORK"
        """
        guard (try? body.write(to: script, atomically: true, encoding: .utf8)) != nil,
              (try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)) != nil
        else { return "Could not write the uninstall helper." }

        // nohup plus & detaches the helper into its own lineage, so quitting
        // this app does not take the helper down with it.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c",
            "nohup \(quoted(script.path)) \(getpid()) \(quoted(work.path)) \(quoted(bundle.path)) >/dev/null 2>&1 &",
        ]
        do {
            try process.run()
        } catch {
            return "Could not start the uninstall helper: \(error.localizedDescription)"
        }
        return nil
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
