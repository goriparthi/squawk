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

final class RedactionTests: XCTestCase {
    /// The dial is on screen during screen shares, so a token in an approval
    /// prompt is a token you have published.
    func testMasksFlagCarriedSecrets() {
        for command in ["psql --password=hunter2 -h db",
                        "deploy --token abc123def456",
                        "curl --api-key=sk_live_9999 https://x"] {
            let out = ToolSummary.redact(command)
            XCTAssertTrue(out.contains("••••"), command)
            for leaked in ["hunter2", "abc123def456", "sk_live_9999"] {
                XCTAssertFalse(out.contains(leaked), "leaked in: \(out)")
            }
        }
    }

    func testMasksAuthorizationHeaders() {
        let out = ToolSummary.redact(#"curl -H "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9" https://x"#)
        XCTAssertFalse(out.contains("eyJhbGciOiJIUzI1NiJ9"))
        XCTAssertTrue(out.contains("Bearer"))
    }

    func testMasksVendorPrefixedKeys() {
        for secret in ["ghp_abcdefghijklmnopqrstuvwxyz123456",
                       "sk-abcdefghijklmnopqrstuvwx",
                       "xoxb-1234567890-abcdefghij",
                       "AKIAIOSFODNN7EXAMPLE"] {
            let out = ToolSummary.redact("deploy \(secret)")
            XCTAssertFalse(out.contains(secret), "leaked \(secret)")
        }
    }

    /// It must not mangle ordinary commands, or every prompt becomes unreadable.
    func testLeavesOrdinaryCommandsIntact() {
        for command in ["npm test --watch=false", "git push origin main",
                        "psql -h db.example.internal -c 'select 1'",
                        "rm -rf build"] {
            XCTAssertEqual(ToolSummary.redact(command), command)
        }
    }

    /// Redaction runs before display, so the summary never carries the secret.
    func testTheSummaryIsRedactedNotJustTheHelper() {
        let summary = ToolSummary.describe(
            tool: "Bash",
            input: ["command": .string("curl --token ghp_abcdefghijklmnopqrstuvwxyz123456 x")],
            cwd: "/tmp"
        )
        XCTAssertFalse(summary.contains("ghp_"))
    }
}

final class InstallStatusTests: XCTestCase {
    private var home: String!
    private var path: String { AgentHost.claudeCode.settingsPath(home: home) }

    override func setUpWithError() throws {
        home = NSTemporaryDirectory() + "squawk-status-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: home + "/.claude", withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: home)
    }

    func testAbsentFileIsMissing() {
        XCTAssertEqual(
            HookInstaller.status(binary: "/opt/squawk-hook", settings: path), .missing
        )
    }

    func testRegisteredAtThisBinaryIsInstalled() {
        _ = HookInstaller.apply(install: true, binary: "/opt/squawk-hook", settings: path)
        XCTAssertEqual(
            HookInstaller.status(binary: "/opt/squawk-hook", settings: path), .installed
        )
    }

    /// Moving the app between Applications folders leaves exactly this, and it
    /// looks identical to the hook simply not working.
    func testAStalePathIsNamedRatherThanCalledMissing() {
        _ = HookInstaller.apply(install: true, binary: "/old/squawk-hook", settings: path)
        XCTAssertEqual(
            HookInstaller.status(binary: "/new/squawk-hook", settings: path),
            .needsUpdate(existing: "/old/squawk-hook")
        )
    }

    /// The notify entry carries a suffix, which must not read as a stale path.
    func testTheNotifySuffixDoesNotLookStale() {
        _ = HookInstaller.apply(install: true, binary: "/opt/squawk-hook", settings: path)
        XCTAssertEqual(
            HookInstaller.status(binary: "/opt/squawk-hook", settings: path), .installed
        )
    }

    func testRubbishJsonIsInvalidNotMissing() throws {
        try Data("{ not json".utf8).write(to: URL(fileURLWithPath: path))
        guard case .invalid = HookInstaller.status(binary: "/opt/squawk-hook", settings: path)
        else { return XCTFail("expected invalid") }
    }

    func testDuplicatesAreAConflict() throws {
        let doubled: [String: Any] = ["hooks": ["PreToolUse": [
            ["matcher": "*", "hooks": [["command": "/a/squawk-hook"]]],
            ["matcher": "*", "hooks": [["command": "/b/squawk-hook"]]],
        ]]]
        try JSONSerialization.data(withJSONObject: doubled)
            .write(to: URL(fileURLWithPath: path))
        XCTAssertEqual(
            HookInstaller.status(binary: "/a/squawk-hook", settings: path), .conflict(count: 2)
        )
    }
}
