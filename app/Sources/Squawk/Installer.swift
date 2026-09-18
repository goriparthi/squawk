import AppKit
import SquawkCore

/// Downloading a release and swapping it in. A process cannot replace its own
/// bundle while it runs, so a detached helper waits for this one to exit.
enum Installer {
    /// Updates are only ever swapped in when they carry this exact Developer ID
    /// team. Pinned, so a notarized build from anyone else is still refused.
    static let expectedTeamID = "QX3NQYWX6F"

    enum Staged {
        /// Verified and staged. Calling swap() hands off to the helper.
        case ready(swap: @Sendable () -> Void)
        case failed(String)
    }

    static func stage(dmg: URL, completion: @escaping @Sendable (Staged) -> Void) {
        URLSession.shared.downloadTask(with: dmg) { temporary, _, error in
            if let error {
                completion(.failed("Download failed: \(error.localizedDescription)"))
                return
            }
            guard let temporary else {
                completion(.failed("Download failed"))
                return
            }
            // downloadTask deletes its temp file once this handler returns.
            let manager = FileManager.default
            let work = manager.temporaryDirectory
                .appendingPathComponent("squawk-update-\(UUID().uuidString)")
            let image = work.appendingPathComponent("Squawk.dmg")
            do {
                try manager.createDirectory(at: work, withIntermediateDirectories: true)
                try manager.moveItem(at: temporary, to: image)
            } catch {
                completion(.failed("Could not stage the download"))
                return
            }
            completion(verify(image: image, work: work))
        }.resume()
    }

    private static func verify(image: URL, work: URL) -> Staged {
        let manager = FileManager.default
        func fail(_ message: String) -> Staged {
            try? manager.removeItem(at: work)
            return .failed(message)
        }

        // -mountrandom keeps the volume out of /Volumes and away from collisions.
        let attach = run("/usr/bin/hdiutil", [
            "attach", image.path, "-nobrowse", "-readonly", "-noverify",
            "-mountrandom", manager.temporaryDirectory.path,
        ])
        guard attach.status == 0,
              let mount = attach.output.split(separator: "\n").last?
                .split(separator: "\t").last.map({ String($0).trimmingCharacters(in: .whitespaces) })
        else { return fail("Could not open the downloaded image") }
        defer { _ = run("/usr/bin/hdiutil", ["detach", mount, "-quiet"]) }

        guard let app = (try? manager.contentsOfDirectory(atPath: mount))?
            .first(where: { $0.hasSuffix(".app") })
            .map({ (mount as NSString).appendingPathComponent($0) })
        else { return fail("No app inside the downloaded image") }

        // The team is enforced as a codesign requirement so the match is
        // cryptographic. Grepping codesign's text output would be spoofable by
        // the app's own filename, which the image's author chooses.
        let requirement = "anchor apple generic and certificate leaf[subject.OU] = \"\(expectedTeamID)\""
        func trusted(_ path: String) -> Bool {
            run("/usr/sbin/spctl", ["-a", "-t", "exec", path]).status == 0
                && run("/usr/bin/codesign",
                       ["--verify", "--deep", "--strict", "-R=\(requirement)", path]).status == 0
        }
        guard trusted(app) else { return fail("Update rejected: signature or notarization failed") }

        // ditto, not cp: it preserves the symlinks, ACLs and extended attributes
        // the signature is computed over.
        let staged = work.appendingPathComponent("staged.app")
        guard run("/usr/bin/ditto", [app, staged.path]).status == 0 else {
            return fail("Could not copy the new version")
        }
        // Verify the copy that will actually be installed, not only the one on
        // the image, so a staged copy that lost its stapled ticket is caught.
        guard trusted(staged.path) else {
            return fail("Update rejected: the staged copy failed verification")
        }

        // The installed app is moved aside rather than deleted, so a failed swap
        // can put it back. Deleting first means one bad mv leaves no app at all.
        let script = work.appendingPathComponent("swap.sh")
        let body = """
        #!/bin/bash
        PID=$1; TARGET=$2; STAGED=$3; WORK=$4
        for _ in $(seq 1 150); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
        PREVIOUS="$WORK/previous.app"
        if [ -e "$TARGET" ] && ! mv "$TARGET" "$PREVIOUS"; then
            osascript -e 'display notification "Update failed; the installed app was left untouched." with title "Squawk"' 2>/dev/null
            open "$TARGET"; rm -rf "$WORK"; exit 1
        fi
        if mv "$STAGED" "$TARGET"; then
            open "$TARGET"
        elif [ -e "$PREVIOUS" ] && mv "$PREVIOUS" "$TARGET"; then
            osascript -e 'display notification "Update failed; the previous version was restored." with title "Squawk"' 2>/dev/null
            open "$TARGET"
        else
            osascript -e 'display notification "Update failed; reinstall from the release page." with title "Squawk"' 2>/dev/null
        fi
        rm -rf "$WORK"
        """
        guard (try? body.write(to: script, atomically: true, encoding: .utf8)) != nil,
              (try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)) != nil
        else { return fail("Could not write the update helper") }

        let target = Bundle.main.bundleURL.path
        return .ready(swap: {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [
                "-c",
                "nohup \(quoted(script.path)) \(getpid()) \(quoted(target)) "
                    + "\(quoted(staged.path)) \(quoted(work.path)) >/dev/null 2>&1 &",
            ]
            try? process.run()
        })
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
