import XCTest
@testable import SquawkCore

final class WireTests: XCTestCase {
    func testRequestRoundTripsAsOneNewlineTerminatedFrame() throws {
        let request = PendingRequest(
            id: "toolu_1",
            sessionId: "s1",
            cwd: "/Users/x/proj",
            tool: "Bash",
            summary: "npm test",
            tty: "/dev/ttys001"
        )
        let data = try WireCodec.encode(request)
        XCTAssertEqual(data.last, 0x0A)
        let decoded = try WireCodec.decode(PendingRequest.self, from: data)
        XCTAssertEqual(decoded, request)
    }

    func testDecisionRoundTrips() throws {
        let reply = DecisionReply(id: "toolu_1", decision: .deny, reason: "nope")
        let decoded = try WireCodec.decode(DecisionReply.self, from: try WireCodec.encode(reply))
        XCTAssertEqual(decoded, reply)
    }

    func testSocketPathRejectsAnUnrepresentableLength() {
        XCTAssertTrue(SocketPath.isRepresentable(SocketPath.socket(home: "/Users/x")))
        XCTAssertFalse(SocketPath.isRepresentable("/" + String(repeating: "a", count: 200)))
    }

    func testSocketLivesUnderTheHomeDirectory() {
        XCTAssertEqual(SocketPath.socket(home: "/Users/x"), "/Users/x/.squawk/sock")
    }
}
