import XCTest
@testable import SquawkCore

final class HookInstallerTests: XCTestCase {
    private var home: String!

    override func setUpWithError() throws {
        home = NSTemporaryDirectory() + "squawk-home-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: home + "/.claude", withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: home)
    }

    private var path: String { HookInstaller.settingsPath(home: home) }

    private func read() throws -> [String: Any] {
        let data = try XCTUnwrap(FileManager.default.contents(atPath: path))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func preToolUse(_ root: [String: Any]) -> [[String: Any]] {
        (root["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]] ?? []
    }

    func testInstallsIntoAnAbsentSettingsFile() throws {
        XCTAssertEqual(
            HookInstaller.apply(install: true, binary: "/opt/squawk-hook", settings: path),
            .installed("/opt/squawk-hook")
        )
        XCTAssertEqual(preToolUse(try read()).count, 1)
    }

    // The settings file governs every session, so an unrelated hook must survive.
    func testOtherHooksAreLeftAlone() throws {
        let existing: [String: Any] = [
            "model": "opus",
            "hooks": ["PreToolUse": [[
                "matcher": "Bash",
                "hooks": [["type": "command", "command": "~/.claude/hooks/gitleaks.sh"]],
            ]]],
        ]
        try JSONSerialization.data(withJSONObject: existing)
            .write(to: URL(fileURLWithPath: path))

        _ = HookInstaller.apply(install: true, binary: "/opt/squawk-hook", settings: path)
        let root = try read()
        XCTAssertEqual(root["model"] as? String, "opus")
        let entries = preToolUse(root)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains { !HookInstaller.isSquawk($0) })
    }

    func testInstallingTwiceReplacesRatherThanStacks() throws {
        _ = HookInstaller.apply(install: true, binary: "/old/squawk-hook", settings: path)
        _ = HookInstaller.apply(install: true, binary: "/new/squawk-hook", settings: path)
        let entries = preToolUse(try read())
        XCTAssertEqual(entries.count, 1)
        let command = ((entries[0]["hooks"] as? [[String: Any]])?.first?["command"]) as? String
        XCTAssertEqual(command, "/new/squawk-hook")
    }

    func testUninstallRemovesOnlySquawk() throws {
        let existing: [String: Any] = [
            "hooks": ["PreToolUse": [[
                "matcher": "Bash",
                "hooks": [["type": "command", "command": "~/.claude/hooks/gitleaks.sh"]],
            ]]],
        ]
        try JSONSerialization.data(withJSONObject: existing)
            .write(to: URL(fileURLWithPath: path))

        _ = HookInstaller.apply(install: true, binary: "/opt/squawk-hook", settings: path)
        XCTAssertEqual(
            HookInstaller.apply(install: false, binary: "/opt/squawk-hook", settings: path),
            .removed
        )
        let entries = preToolUse(try read())
        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(HookInstaller.isSquawk(entries[0]))
    }

    /// Better to refuse than to overwrite a file we could not understand.
    func testMalformedSettingsAreRefusedNotOverwritten() throws {
        try Data("{ not json".utf8).write(to: URL(fileURLWithPath: path))
        guard case .failed = HookInstaller.apply(
            install: true, binary: "/opt/squawk-hook", settings: path
        ) else { return XCTFail("expected a refusal") }
        XCTAssertEqual(
            try String(contentsOfFile: path, encoding: .utf8), "{ not json"
        )
    }

    func testABackupIsWrittenBeforeChanging() throws {
        try Data("{}".utf8).write(to: URL(fileURLWithPath: path))
        _ = HookInstaller.apply(install: true, binary: "/opt/squawk-hook", settings: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path + ".squawk-backup"))
    }
}

final class CodexInstallerTests: XCTestCase {
    private var home: String!

    override func setUpWithError() throws {
        home = NSTemporaryDirectory() + "squawk-codex-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: home + "/.codex", withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: home)
    }

    private var path: String { AgentHost.codex.settingsPath(home: home) }

    private func entries() throws -> [[String: Any]] {
        let data = try XCTUnwrap(FileManager.default.contents(atPath: path))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (root["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]] ?? []
    }

    func testCodexUsesItsOwnPath() {
        XCTAssertTrue(AgentHost.codex.settingsPath(home: "/Users/x").hasSuffix(".codex/hooks.json"))
        XCTAssertTrue(AgentHost.claudeCode.settingsPath(home: "/Users/x").hasSuffix(".claude/settings.json"))
    }

    /// Codex takes the command flat; Claude Code nests it under a matcher.
    func testCodexEntryIsFlat() throws {
        _ = HookInstaller.apply(install: true, binary: "/opt/squawk-hook", host: .codex, settings: path)
        let entry = try XCTUnwrap(entries().first)
        XCTAssertEqual(entry["command"] as? String, "/opt/squawk-hook")
        XCTAssertNil(entry["hooks"], "Codex does not nest handlers")
        XCTAssertNil(entry["matcher"], "Codex has no matcher")
    }

    func testBothShapesAreRecognisedAsOurs() {
        XCTAssertTrue(HookInstaller.isSquawk(["command": "/opt/squawk-hook"]))
        XCTAssertTrue(HookInstaller.isSquawk([
            "matcher": "*", "hooks": [["type": "command", "command": "/opt/squawk-hook"]],
        ]))
        XCTAssertFalse(HookInstaller.isSquawk(["command": "/opt/something-else"]))
    }

    func testReinstallReplacesTheCodexEntry() throws {
        _ = HookInstaller.apply(install: true, binary: "/old/squawk-hook", host: .codex, settings: path)
        _ = HookInstaller.apply(install: true, binary: "/new/squawk-hook", host: .codex, settings: path)
        XCTAssertEqual(try entries().count, 1)
        XCTAssertEqual(try entries().first?["command"] as? String, "/new/squawk-hook")
    }

    func testCodexUninstallLeavesOtherHooks() throws {
        let existing: [String: Any] = ["hooks": ["PreToolUse": [["command": "/opt/audit.sh"]]]]
        try JSONSerialization.data(withJSONObject: existing)
            .write(to: URL(fileURLWithPath: path))
        _ = HookInstaller.apply(install: true, binary: "/opt/squawk-hook", host: .codex, settings: path)
        XCTAssertEqual(try entries().count, 2)
        _ = HookInstaller.apply(install: false, binary: "/opt/squawk-hook", host: .codex, settings: path)
        XCTAssertEqual(try entries().map { $0["command"] as? String }, ["/opt/audit.sh"])
    }
}
