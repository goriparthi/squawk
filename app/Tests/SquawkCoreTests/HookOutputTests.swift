import XCTest
@testable import SquawkCore

final class HookOutputTests: XCTestCase {
    func testAllowMatchesTheDocumentedShape() {
        let json = HookOutput.json(for: .allow)
        XCTAssertEqual(
            json,
            #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}"#
        )
    }

    func testDenyAlwaysCarriesAReasonBecauseClaudeCodeRequiresOne() {
        let json = HookOutput.json(for: .deny, reason: nil)
        XCTAssertTrue(json.contains(#""permissionDecision":"deny""#))
        XCTAssertTrue(json.contains("permissionDecisionReason"))
    }

    func testHookInputDecodesTheRealPayload() throws {
        let payload = Data(#"""
        {"session_id":"abc","cwd":"/Users/x/p","hook_event_name":"PreToolUse",
         "tool_name":"Bash","tool_use_id":"toolu_1","permission_mode":"default",
         "tool_input":{"command":"npm test","timeout":120000}}
        """#.utf8)
        let input = try JSONDecoder().decode(HookInput.self, from: payload)
        XCTAssertEqual(input.sessionId, "abc")
        XCTAssertEqual(input.toolUseId, "toolu_1")
        XCTAssertEqual(input.toolInput?["command"]?.stringValue, "npm test")
    }
}

final class AgentEventTests: XCTestCase {
    /// The two agents do not share a reply shape. Codex nests the decision under
    /// `decision.behavior`; sending Claude Code's flat form would be ignored.
    func testCodexRepliesInItsOwnShape() throws {
        let json = HookOutput.json(for: .allow, event: .permissionRequest)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        )
        let specific = try XCTUnwrap(root["hookSpecificOutput"] as? [String: Any])
        XCTAssertEqual(specific["hookEventName"] as? String, "PermissionRequest")
        let decision = try XCTUnwrap(specific["decision"] as? [String: Any])
        XCTAssertEqual(decision["behavior"] as? String, "allow")
        XCTAssertNil(specific["permissionDecision"], "that is Claude Code's shape")
    }

    func testCodexDenyCarriesAMessage() throws {
        let json = HookOutput.json(for: .deny, reason: nil, event: .permissionRequest)
        XCTAssertTrue(json.contains("\"behavior\":\"deny\""))
        XCTAssertTrue(json.contains("message"))
    }

    func testClaudeCodeShapeIsUnchanged() {
        XCTAssertEqual(
            HookOutput.json(for: .allow, event: .preToolUse),
            #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}"#
        )
    }

    /// PermissionRequest only fires when the agent was going to ask, so filtering
    /// it by permission mode would drop the very prompts Squawk exists for.
    func testOnlyPreToolUseIsFilteredByMode() {
        XCTAssertTrue(AgentEvent.preToolUse.respectsGatePolicy)
        XCTAssertFalse(AgentEvent.permissionRequest.respectsGatePolicy)
    }

    func testUnknownEventFallsBackToPreToolUse() {
        XCTAssertEqual(AgentEvent.named(nil), .preToolUse)
        XCTAssertEqual(AgentEvent.named("Whatever"), .preToolUse)
        XCTAssertEqual(AgentEvent.named("PermissionRequest"), .permissionRequest)
    }

    /// Codex sends a turn, not a tool call, so a missing tool_use_id must not
    /// fail the decode and drop the request.
    func testCodexPayloadDecodesWithoutAToolUseId() throws {
        let payload = Data(#"""
        {"session_id":"s","cwd":"/x","hook_event_name":"PermissionRequest",
         "permission_mode":"default","turn_id":"t-9","tool_name":"Bash",
         "tool_input":{"command":"ls"}}
        """#.utf8)
        let input = try JSONDecoder().decode(HookInput.self, from: payload)
        XCTAssertEqual(input.event, .permissionRequest)
        XCTAssertNil(input.toolUseId)
        XCTAssertEqual(input.requestId, "turn:t-9")
    }

    func testEachHostRegistersItsOwnDecisionEvent() {
        XCTAssertEqual(AgentHost.claudeCode.decisionEvent, "PreToolUse")
        XCTAssertEqual(AgentHost.codex.decisionEvent, "PermissionRequest")
        XCTAssertNil(AgentHost.codex.notificationEvent)
    }
}
