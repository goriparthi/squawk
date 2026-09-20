import XCTest
@testable import SquawkCore

final class MCPTests: XCTestCase {
    private func answer(
        _ json: String,
        speak: @escaping (String) -> MCP.Spoken = { text in MCP.Spoken(spoke: true, detail: "said \(text)") }
    ) -> [String: Any]? {
        guard let data = MCP.respond(to: Data(json.utf8), version: "1.2.3", speak: speak)
        else { return nil }
        XCTAssertEqual(data.last, 0x0A, "every frame is one line")
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    func testInitializeNamesTheServerAndTheRevision() throws {
        let reply = try XCTUnwrap(answer(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#
        ))
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(reply["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(result["protocolVersion"] as? String, MCP.protocolVersion)
        let info = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(info["name"] as? String, MCP.serverName)
        XCTAssertEqual(info["version"] as? String, "1.2.3")
        XCTAssertNotNil(result["capabilities"] as? [String: Any])
    }

    /// An id may be a string or a number, and it has to come back exactly as it
    /// went out or the client cannot match the reply to its call.
    func testTheIdComesBackAsItArrived() throws {
        let numeric = try XCTUnwrap(answer(#"{"jsonrpc":"2.0","id":7,"method":"ping"}"#))
        XCTAssertEqual(numeric["id"] as? Int, 7)
        let text = try XCTUnwrap(answer(#"{"jsonrpc":"2.0","id":"abc","method":"ping"}"#))
        XCTAssertEqual(text["id"] as? String, "abc")
    }

    func testTheToolIsListedWithItsSchema() throws {
        let reply = try XCTUnwrap(answer(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        let tools = try XCTUnwrap(
            (reply["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        )
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0]["name"] as? String, MCP.toolName)
        let schema = try XCTUnwrap(tools[0]["inputSchema"] as? [String: Any])
        XCTAssertEqual(schema["required"] as? [String], ["text"])
        XCTAssertNotNil((schema["properties"] as? [String: Any])?["text"])
    }

    func testCallingSpeakPassesTheTextThrough() throws {
        var heard: String?
        let reply = try XCTUnwrap(answer(
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"speak","arguments":{"text":"tests are green"}}}"#
        ) { text in
            heard = text
            return MCP.Spoken(spoke: true, detail: "Said out loud: \(text)")
        })
        XCTAssertEqual(heard, "tests are green")
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[0]["text"] as? String, "Said out loud: tests are green")
    }

    /// The pet declining to say something is the tool's own result, not a
    /// protocol failure: nothing went wrong with the call.
    func testARefusalIsAToolResultAndNotAProtocolError() throws {
        let reply = try XCTUnwrap(answer(
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"speak","arguments":{"text":"x"}}}"#
        ) { _ in MCP.Spoken(spoke: false, detail: "Squawk says at most 6 lines a minute.") })
        XCTAssertNil(reply["error"])
        let result = try XCTUnwrap(reply["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
    }

    func testSpeakWithoutTextIsRejectedBeforeAnythingIsSaid() throws {
        var asked = false
        let reply = try XCTUnwrap(answer(
            #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"speak","arguments":{}}}"#
        ) { _ in
            asked = true
            return MCP.Spoken(spoke: true, detail: "")
        })
        XCTAssertFalse(asked)
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32602)
    }

    func testAnUnknownToolIsRejected() throws {
        let reply = try XCTUnwrap(answer(
            #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"approve","arguments":{}}}"#
        ))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32602)
    }

    /// Replying to a notification is a protocol error, and a client is entitled
    /// to drop the server over one.
    func testANotificationIsAnsweredWithSilence() {
        XCTAssertNil(MCP.respond(
            to: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
        ) { _ in MCP.Spoken(spoke: true, detail: "") })
    }

    func testAnUnknownMethodWithAnIdIsAnError() throws {
        let reply = try XCTUnwrap(answer(#"{"jsonrpc":"2.0","id":8,"method":"resources/list"}"#))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32601)
    }

    func testGarbageIsAnsweredRatherThanCrashing() throws {
        let reply = try XCTUnwrap(answer("not json at all"))
        XCTAssertEqual((reply["error"] as? [String: Any])?["code"] as? Int, -32700)
        XCTAssertTrue(reply["id"] is NSNull)
    }

    /// A null id is not an id, so it must not come back as one to be matched.
    func testANullIdIsNotEchoedAsAnId() throws {
        let reply = try XCTUnwrap(answer(#"{"jsonrpc":"2.0","id":null,"method":"ping"}"#))
        XCTAssertTrue(reply["id"] is NSNull)
    }

    // MARK: - Registration, which is read and never written

    func testRegistrationIsRecognisedByCommandRatherThanByName() throws {
        let path = NSTemporaryDirectory() + "/mcp-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let binary = "/Applications/Squawk.app/Contents/Helpers/squawk-hook"

        try #"{"mcpServers":{"anything":{"command":"\#(binary)","args":["--mcp"]}}}"#
            .write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(MCPRegistration.status(binary: binary, path: path), .installed)
    }

    /// A stale path is the failure that looks most like the app being broken,
    /// so it names where it is actually pointing.
    func testAStalePathNamesItself() throws {
        let path = NSTemporaryDirectory() + "/mcp-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try #"{"mcpServers":{"squawk":{"command":"/old/squawk-hook","args":["--mcp"]}}}"#
            .write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(
            MCPRegistration.status(binary: "/new/squawk-hook", path: path),
            .needsUpdate(existing: "/old/squawk-hook")
        )
    }

    func testNoEntryAtAllIsMissing() throws {
        let path = NSTemporaryDirectory() + "/mcp-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try #"{"mcpServers":{"other":{"command":"/usr/bin/other"}}}"#
            .write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(MCPRegistration.status(binary: "/x/squawk-hook", path: path), .missing)
        XCTAssertEqual(
            MCPRegistration.status(binary: "/x/squawk-hook", path: path + ".absent"), .missing
        )
    }

    func testAnUnreadableConfigIsNotAssumedEmpty() throws {
        let path = NSTemporaryDirectory() + "/mcp-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try "{ not json".write(toFile: path, atomically: true, encoding: .utf8)
        guard case .invalid = MCPRegistration.status(binary: "/x/squawk-hook", path: path) else {
            return XCTFail("an unreadable config read as missing")
        }
    }

    func testTheCommandItPrintsRegistersThisBinary() {
        XCTAssertEqual(
            MCPRegistration.addCommand(binary: "/x/squawk-hook"),
            "claude mcp add squawk -- /x/squawk-hook --mcp"
        )
    }
}
