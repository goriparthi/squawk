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

    func testScriptIsNilForARejectedTTY() {
        XCTAssertNil(PaneFocus.script(forTTY: "/etc/passwd"))
    }

    func testScriptEmbedsTheTTY() throws {
        let script = try XCTUnwrap(PaneFocus.script(forTTY: "/dev/ttys007"))
        XCTAssertTrue(script.contains("/dev/ttys007"))
        XCTAssertTrue(script.contains("iTerm2"))
    }
}
