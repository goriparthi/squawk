import XCTest
@testable import SquawkCore

final class ToolSummaryTests: XCTestCase {
    func testBashShowsTheCommand() {
        let summary = ToolSummary.describe(
            tool: "Bash",
            input: ["command": .string("rm -rf build")],
            cwd: "/Users/x/proj"
        )
        XCTAssertEqual(summary, "rm -rf build")
    }

    func testEditShowsPathRelativeToSession() {
        let summary = ToolSummary.describe(
            tool: "Edit",
            input: ["file_path": .string("/Users/x/proj/src/main.swift")],
            cwd: "/Users/x/proj"
        )
        XCTAssertEqual(summary, "src/main.swift")
    }

    func testUnknownToolFallsBackToItsName() {
        XCTAssertEqual(ToolSummary.describe(tool: "Mystery", input: [:], cwd: "/tmp"), "Mystery")
    }

    func testMissingInputFallsBackToItsName() {
        XCTAssertEqual(ToolSummary.describe(tool: "Bash", input: nil, cwd: "/tmp"), "Bash")
    }

    func testControlCharactersAreStripped() {
        let summary = ToolSummary.sanitize("git\u{1B}[31m status\n\nnow")
        XCTAssertFalse(summary.contains("\u{1B}"))
        XCTAssertFalse(summary.contains("\n"))
        XCTAssertEqual(summary, "git [31m status now")
    }

    func testTruncationKeepsTheLimitIncludingTheEllipsis() {
        let truncated = ToolSummary.truncate(String(repeating: "x", count: 50), to: 10)
        XCTAssertEqual(truncated.count, 10)
        XCTAssertTrue(truncated.hasSuffix("\u{2026}"))
    }

    func testShortTextIsNotTruncated() {
        XCTAssertEqual(ToolSummary.truncate("short", to: 10), "short")
    }

    func testPathOutsideSessionFallsBackToTilde() {
        let path = ToolSummary.relativize(NSHomeDirectory() + "/elsewhere/a.txt", to: "/Users/x/proj")
        XCTAssertEqual(path, "~/elsewhere/a.txt")
    }
}
