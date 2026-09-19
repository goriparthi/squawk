import XCTest
@testable import SquawkCore

final class MusicPresenceTests: XCTestCase {
    /// Energy concentrated in the two speech bands with nothing underneath.
    private var talking: Spectrum {
        Spectrum(bands: [0.05, 0.2, 0.7, 0.6, 0.15],
                 energy: [0.02, 0.10, 0.50, 0.32, 0.06], level: 0.35)
    }
    /// A kick and a bassline holding the bottom, and some air on top.
    private var music: Spectrum {
        Spectrum(bands: [0.8, 0.6, 0.5, 0.4, 0.45],
                 energy: [0.34, 0.22, 0.18, 0.14, 0.12], level: 0.5)
    }

    private func run(_ presence: inout MusicPresence, _ spectrum: Spectrum,
                     seconds: Double, hasTempo: Bool = false, from start: Double = 0) -> Bool {
        var playing = false
        var now = start
        // The rate blocks actually arrive at from the tap.
        while now < start + seconds {
            playing = presence.update(spectrum, hasTempo: hasTempo, at: now)
            now += 1.0 / 93
        }
        return playing
    }

    /// The whole point: a call, a video or a spoken reply is not music, and the
    /// pet should not put headphones on for it.
    func testTalkingIsNotMusic() {
        var presence = MusicPresence()
        XCTAssertFalse(run(&presence, talking, seconds: 20))
    }

    func testMusicIsMusic() {
        var presence = MusicPresence()
        XCTAssertTrue(run(&presence, music, seconds: 20))
    }

    /// A tempo is something only music has, and settles it on its own.
    func testADetectedBeatIsEnough() {
        var presence = MusicPresence()
        XCTAssertTrue(run(&presence, talking, seconds: 20, hasTempo: true))
    }

    /// A notification is over before anything could be decided about it.
    func testAShortSoundIsNeverMusic() {
        var presence = MusicPresence()
        XCTAssertFalse(run(&presence, music, seconds: 2))
    }

    /// Someone puts a track on during a call: it still has to notice.
    func testItKeepsWatchingAfterTheSoundStarted() {
        var presence = MusicPresence()
        XCTAssertFalse(run(&presence, talking, seconds: 20))
        XCTAssertTrue(run(&presence, music, seconds: 30, from: 20))
    }

    func testItStopsWhenTheSoundDoes() {
        var presence = MusicPresence()
        XCTAssertTrue(run(&presence, music, seconds: 20))
        XCTAssertFalse(run(&presence, .silent, seconds: 2, from: 20))
    }

    func testOneSpectrumIsJudgedOnItsShape() {
        XCTAssertTrue(MusicPresence.looksMusical(music))
        XCTAssertFalse(MusicPresence.looksMusical(talking))
        XCTAssertFalse(MusicPresence.looksMusical(.silent))
    }
}
