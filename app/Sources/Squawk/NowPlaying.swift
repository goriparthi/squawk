import AppKit
import SquawkCore

/// What is playing, when it can be known by asking.
///
/// The system wide now playing information lives behind MediaRemote, which is
/// private and which Apple has been closing off, so this asks the two players
/// that expose a public scripting interface and says nothing rather than
/// guessing for anything else. The tap still knows there is sound and what
/// tempo it is, whoever is making it.
@MainActor
enum NowPlaying {
    struct Track: Equatable {
        var title: String
        var artist: String
        /// Which player it came from, so the card can say.
        var source: String
        /// Cover art, when the player will hand it over.
        var artwork: NSImage?

        static func == (lhs: Track, rhs: Track) -> Bool {
            lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.source == rhs.source
        }
    }

    /// The players worth asking, and the script that asks them. Both expose
    /// this deliberately; neither needs anything private.
    private static let players: [(bundle: String, name: String)] = [
        ("com.apple.Music", "Music"),
        ("com.spotify.client", "Spotify"),
    ]

    /// Nil when nothing scriptable is playing, which includes a browser tab,
    /// a video call, or anything else making noise.
    static func current() -> Track? {
        for player in players {
            guard isRunning(player.bundle) else { continue }
            guard let track = ask(player.name) else { continue }
            return track
        }
        return nil
    }

    /// Cover art, for the players that will hand it over. Music returns the
    /// bytes; Spotify returns a URL, which is not fetched: a desk toy has no
    /// business making network requests to draw a thumbnail.
    private static func artwork(from application: String) -> NSImage? {
        guard application == "Music" else { return nil }
        let source = """
        tell application "Music"
            if player state is playing then
                return data of artwork 1 of current track
            end if
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, let data = result.data as Data? else { return nil }
        return NSImage(data: data)
    }

    /// When no scriptable player is running, the machine can still say which
    /// application is making the sound, which is more than "something is".
    static func playingApplication() -> String? {
        let playing = PrivacyWatch.applicationsPlaying()
        // Skip the ones that are always making a noise about something.
        let ignored: Set<String> = ["loginwindow", "Notification Centre", "Notification Center"]
        return playing
            .compactMap(\.localizedName)
            .first { !ignored.contains($0) }
    }

    private static func isRunning(_ bundle: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
    }

    /// What each player says, errors included, for working out why a card came
    /// back empty when something is obviously playing.
    static func diagnose() -> [String] {
        players.map { player in
            guard isRunning(player.bundle) else { return "\(player.name): not running" }
            var error: NSDictionary?
            let source = """
            tell application "\(player.name)"
                return (player state as text)
            end tell
            """
            guard let script = NSAppleScript(source: source) else {
                return "\(player.name): running, script would not compile"
            }
            let result = script.executeAndReturnError(&error)
            if let error {
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                let hint = code == -1743
                    ? " (no Automation permission: System Settings, Privacy and Security, Automation)"
                    : ""
                return "\(player.name): running, but the script failed with \(code)\(hint)"
            }
            let state = result.stringValue ?? "?"
            let track = ask(player.name)
            return "\(player.name): running, player state \(state), track "
                + (track.map { "\($0.title) by \($0.artist)" } ?? "not readable")
        }
    }

    private static func ask(_ application: String) -> Track? {
        // Only while it is actually playing: a paused player still knows its
        // track, and a card naming it would be wrong about the thing it is
        // answering, which is what is making the sound right now.
        let source = """
        tell application "\(application)"
            if player state is playing then
                return (name of current track) & "\u{1}" & (artist of current track)
            end if
        end tell
        """
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        guard let joined = result.stringValue else { return nil }
        let parts = joined.components(separatedBy: "\u{1}")
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        return Track(title: parts[0], artist: parts[1], source: application,
                     artwork: artwork(from: application))
    }
}
