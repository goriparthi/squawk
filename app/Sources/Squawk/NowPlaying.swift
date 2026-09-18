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

    private static func isRunning(_ bundle: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty
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
        return Track(title: parts[0], artist: parts[1], source: application)
    }
}
