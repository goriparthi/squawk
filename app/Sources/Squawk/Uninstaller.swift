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

    /// Every copy macOS knows about, not just the one this process happens to
    /// be running from. Installing from a DMG as well as from a build leaves two,
    /// and removing only the running one looks exactly like uninstall failing.
    static func installedCopies() -> [URL] {
        var seen = Set<String>()
        var copies: [URL] = []
        for url in NSWorkspace.shared.urlsForApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.goriparthi.squawk"
        ) where url.pathExtension == "app" {
            let path = url.resolvingSymlinksInPath().path
            if seen.insert(path).inserted { copies.append(url) }
        }
        // The running copy may not be registered yet on a first launch.
        let running = Bundle.main.bundleURL
        if running.pathExtension == "app",
           seen.insert(running.resolvingSymlinksInPath().path).inserted {
            copies.append(running)
        }
        return copies
    }

    /// Hands the bundles to a detached helper that waits for this process to
    /// exit. They go to the Trash rather than being deleted, so an uninstall
    /// someone regrets is one Put Back away.
    static func trashBundlesAfterQuit(_ bundles: [URL]) -> String? {
        guard !bundles.isEmpty else { return nil }

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
        PID=$1; WORK=$2; shift 2
        for _ in $(seq 1 150); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
        mkdir -p "$HOME/.Trash"
        FAILED=0
        for TARGET in "$@"; do
            [ -e "$TARGET" ] || continue
            DEST="$HOME/.Trash/$(basename "$TARGET")"
            [ -e "$DEST" ] && DEST="$HOME/.Trash/Squawk $(date +%Y-%m-%d-%H%M%S).app"
            mv "$TARGET" "$DEST" || FAILED=$((FAILED + 1))
        done
        if [ "$FAILED" -gt 0 ]; then
            osascript -e "display notification \"$FAILED copy could not be moved to the Trash. Drag it there from your Applications folder.\" with title \"Squawk\"" 2>/dev/null
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
        let targets = bundles.map { quoted($0.path) }.joined(separator: " ")
        process.arguments = [
            "-c",
            "nohup \(quoted(script.path)) \(getpid()) \(quoted(work.path)) \(targets) >/dev/null 2>&1 &",
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
