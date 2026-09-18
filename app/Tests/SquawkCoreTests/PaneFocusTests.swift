import XCTest
@testable import SquawkCore

final class PaneFocusTests: XCTestCase {
    func testAcceptsRealDarwinTTYs() {
        XCTAssertTrue(PaneFocus.isValidTTY("/dev/ttys000"))
        XCTAssertTrue(PaneFocus.isValidTTY("/dev/ttys012"))
    }

    // The tty is interpolated into AppleScript, so anything that could close the
    // string literal has to be refused rather than escaped.
    func testRejectsInjectionAttempts() {
        XCTAssertFalse(PaneFocus.isValidTTY("/dev/ttys000\" & (do shell script \"id\") & \""))
        XCTAssertFalse(PaneFocus.isValidTTY("/dev/tty s000"))
        XCTAssertFalse(PaneFocus.isValidTTY("/dev/tty"))
        XCTAssertFalse(PaneFocus.isValidTTY("/etc/passwd"))
        XCTAssertFalse(PaneFocus.isValidTTY(""))
    }

    func testTTYTerminalsEmbedTheDevicePath() throws {
        for terminal in [PaneFocus.Terminal.iTerm2, .appleTerminal] {
            let script = try XCTUnwrap(
                PaneFocus.script(for: terminal, tty: "/dev/ttys007", cwd: "/tmp")
            )
            XCTAssertTrue(script.contains("/dev/ttys007"), "\(terminal)")
            XCTAssertTrue(script.contains(terminal.applicationName), "\(terminal)")
        }
    }

    func testTTYTerminalsRefuseABadDevicePath() {
        for terminal in [PaneFocus.Terminal.iTerm2, .appleTerminal] {
            XCTAssertNil(PaneFocus.script(for: terminal, tty: "/etc/passwd", cwd: "/tmp"))
            XCTAssertNil(PaneFocus.script(for: terminal, tty: nil, cwd: "/tmp"))
        }
    }

    // Ghostty's AppleScript exposes no tty, so it matches on working directory.
    func testGhosttyMatchesOnWorkingDirectory() throws {
        let script = try XCTUnwrap(
            PaneFocus.script(for: .ghostty, tty: nil, cwd: "/Users/x/proj")
        )
        XCTAssertTrue(script.contains("working directory"))
        XCTAssertTrue(script.contains("/Users/x/proj"))
        // Not `contains("tty")`: the application name Ghostty contains it too.
        XCTAssertFalse(script.contains("tty of"))
    }

    func testGhosttyNeedsADirectory() {
        XCTAssertNil(PaneFocus.script(for: .ghostty, tty: "/dev/ttys001", cwd: ""))
    }

    // A directory is freeform, so it is escaped rather than refused. A quote in
    // a path would otherwise close the literal and run whatever followed.
    func testDirectoryLiteralIsEscaped() {
        XCTAssertEqual(PaneFocus.literal("/tmp/plain"), "\"/tmp/plain\"")
        // Every inner quote comes back escaped, so the literal cannot be closed
        // early and nothing after it is evaluated as AppleScript.
        XCTAssertEqual(
            PaneFocus.literal("/tmp/a\" & (do shell script \"id\") & \"b"),
            "\"/tmp/a\\\" & (do shell script \\\"id\\\") & \\\"b\""
        )
        XCTAssertEqual(PaneFocus.literal("back\\slash"), "\"back\\\\slash\"")
    }

    func testOnlyGhosttyIsApproximate() {
        XCTAssertTrue(PaneFocus.Terminal.iTerm2.matchesExactly)
        XCTAssertTrue(PaneFocus.Terminal.appleTerminal.matchesExactly)
        XCTAssertFalse(PaneFocus.Terminal.ghostty.matchesExactly)
    }
}

final class ProcessTreeTests: XCTestCase {
    // The chain is what tells Squawk which terminal a request came from.
    func testAncestorsReachAtLeastTheParent() {
        let chain = ProcessTree.ancestors()
        XCTAssertFalse(chain.isEmpty)
        XCTAssertEqual(chain.first, getppid())
    }

    func testAncestorsAreBounded() {
        XCTAssertLessThanOrEqual(ProcessTree.ancestors(limit: 3).count, 3)
    }

    func testUnknownPidHasNoParent() {
        XCTAssertNil(ProcessTree.parent(of: 999_999))
    }
}
