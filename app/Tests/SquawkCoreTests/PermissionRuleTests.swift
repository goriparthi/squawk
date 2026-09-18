import XCTest
@testable import SquawkCore

final class PermissionRuleTests: XCTestCase {
    func testBashRuleIsTwoLeadingWords() {
        let rule = PermissionRule.key(tool: "Bash", summary: "git push --force origin main")
        XCTAssertEqual(rule.prefix, "git push")
    }

    /// One word would wave through every git command, including the destructive
    /// ones; the whole line would never match a second time.
    func testScopeIsNeitherEverythingNorNothing() {
        let rule = PermissionRule.key(tool: "Bash", summary: "git push --force origin main")
        XCTAssertTrue(rule.matches(tool: "Bash", summary: "git push origin feature"))
        XCTAssertFalse(rule.matches(tool: "Bash", summary: "git reset --hard"))
        XCTAssertFalse(rule.matches(tool: "Bash", summary: "rm -rf build"))
    }

    func testNonBashToolsRuleOnTheToolAlone() {
        let rule = PermissionRule.key(tool: "Read", summary: "src/main.swift")
        XCTAssertEqual(rule.prefix, "")
        XCTAssertTrue(rule.matches(tool: "Read", summary: "anything/else.swift"))
        XCTAssertFalse(rule.matches(tool: "Write", summary: "anything/else.swift"))
    }

    func testScopeIsDescribedBeforeItIsGranted() {
        XCTAssertEqual(
            PermissionRule.key(tool: "Bash", summary: "npm test --watch").describedScope,
            "npm test …"
        )
        XCTAssertEqual(
            PermissionRule.key(tool: "Read", summary: "x").describedScope,
            "every Read call"
        )
    }

    func testSingleWordCommandStillMakesARule() {
        XCTAssertEqual(PermissionRule.key(tool: "Bash", summary: "ls").prefix, "ls")
    }
}

final class RuleStoreTests: XCTestCase {
    func testSessionRuleDoesNotLeakToAnotherSession() {
        var store = RuleStore()
        store.remember(tool: "Bash", summary: "npm test", sessionId: "s1", forever: false)
        XCTAssertTrue(store.allows(tool: "Bash", summary: "npm test x", sessionId: "s1"))
        XCTAssertFalse(store.allows(tool: "Bash", summary: "npm test x", sessionId: "s2"))
    }

    func testAlwaysRuleAppliesEverywhere() {
        var store = RuleStore()
        store.remember(tool: "Bash", summary: "npm test", sessionId: "s1", forever: true)
        XCTAssertTrue(store.allows(tool: "Bash", summary: "npm test x", sessionId: "s2"))
    }

    func testForgettingASessionLeavesAlwaysRules() {
        var store = RuleStore()
        store.remember(tool: "Bash", summary: "npm test", sessionId: "s1", forever: false)
        store.remember(tool: "Bash", summary: "git status", sessionId: "s1", forever: true)
        store.forgetSession("s1")
        XCTAssertFalse(store.allows(tool: "Bash", summary: "npm test", sessionId: "s1"))
        XCTAssertTrue(store.allows(tool: "Bash", summary: "git status", sessionId: "s1"))
    }

    func testRulesRoundTripThroughDisk() {
        let path = NSTemporaryDirectory() + "squawk-rules-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let rules: Set<PermissionRule> = [
            .init(tool: "Bash", prefix: "git status"),
            .init(tool: "Read", prefix: ""),
        ]
        RuleFile.save(rules, path: path)
        XCTAssertEqual(RuleFile.load(path: path), rules)
    }

    /// A rule is standing permission to run something, so the file is not world
    /// readable.
    func testRuleFileIsPrivate() throws {
        let path = NSTemporaryDirectory() + "squawk-rules-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }
        RuleFile.save([.init(tool: "Bash", prefix: "ls")], path: path)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, 0o600)
    }

    func testMissingFileIsNoRules() {
        XCTAssertTrue(RuleFile.load(path: "/nonexistent/squawk/rules.json").isEmpty)
    }
}

final class GatePolicyTests: XCTestCase {
    /// The bug this exists for: gating every mode turned silent auto-approval
    /// into a dial prompt for calls Claude Code would never have stopped on.
    func testOnlyModesThatWouldPromptAreGated() {
        XCTAssertTrue(GatePolicy.shouldGate(mode: "default"))
        XCTAssertTrue(GatePolicy.shouldGate(mode: "acceptEdits"))
        XCTAssertFalse(GatePolicy.shouldGate(mode: "auto"))
        XCTAssertFalse(GatePolicy.shouldGate(mode: "bypassPermissions"))
        XCTAssertFalse(GatePolicy.shouldGate(mode: "plan"))
    }

    /// Observed in real transcripts: these sessions run "auto", and gating it
    /// turned silent auto-approval into a dial prompt on every call.
    func testAutoIsNotGated() {
        XCTAssertFalse(GatePolicy.shouldGate(mode: "auto"))
    }

    func testAnUnknownOrAbsentModeDoesNotGate() {
        XCTAssertFalse(GatePolicy.shouldGate(mode: nil))
        XCTAssertFalse(GatePolicy.shouldGate(mode: ""))
        XCTAssertFalse(GatePolicy.shouldGate(mode: "somethingNew"))
    }

    func testModesAreOverridable() {
        XCTAssertEqual(GatePolicy.modes(from: "default,auto"), ["default", "auto"])
        XCTAssertEqual(GatePolicy.modes(from: " default , auto "), ["default", "auto"])
        XCTAssertEqual(GatePolicy.modes(from: nil), GatePolicy.defaultModes)
        XCTAssertEqual(GatePolicy.modes(from: "  "), GatePolicy.defaultModes)
        XCTAssertTrue(GatePolicy.shouldGate(mode: "auto", allowed: GatePolicy.modes(from: "default,auto")))
    }
}

final class RuleScopeRegressionTests: XCTestCase {
    /// The exact shape that went wrong in use: a remembered `git push` must not
    /// wave through `rm -rf`.
    func testRememberingOneCommandDoesNotAllowAnother() {
        var store = RuleStore()
        store.remember(tool: "Bash", summary: "git push --force origin main",
                       sessionId: "s1", forever: false)
        XCTAssertTrue(store.allows(tool: "Bash", summary: "git push origin feature", sessionId: "s1"))
        XCTAssertFalse(store.allows(tool: "Bash", summary: "rm -rf build", sessionId: "s1"))
        XCTAssertFalse(store.allows(tool: "Bash", summary: "curl evil.example", sessionId: "s1"))
    }

    func testAnEmptyStoreAllowsNothing() {
        let store = RuleStore()
        XCTAssertFalse(store.allows(tool: "Bash", summary: "rm -rf build", sessionId: "s1"))
        XCTAssertFalse(store.allows(tool: "Read", summary: "x", sessionId: "s1"))
    }
}
