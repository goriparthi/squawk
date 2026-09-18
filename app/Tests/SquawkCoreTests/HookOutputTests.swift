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
