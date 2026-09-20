import Foundation

/// Squawk as an MCP server: one tool, `speak`, which puts a line in the pet's
/// mouth. Hand rolled JSON-RPC because the app ships no package dependencies.
///
/// The whole protocol is a pure function of the line that arrived, so it is
/// tested without a pipe, a process or a socket.
public enum MCP {
    /// The revision this server implements. A client naming another one is
    /// answered with this, and decides for itself whether it can live with it.
    public static let protocolVersion = "2025-06-18"
    public static let serverName = "squawk"
    public static let toolName = "speak"

    /// What the app said back about a line.
    public struct Spoken: Sendable, Equatable {
        public let spoke: Bool
        public let detail: String

        public init(spoke: Bool, detail: String) {
            self.spoke = spoke
            self.detail = detail
        }
    }

    /// The description is the prompt the agent actually reads, so it says what
    /// this is for, what it is not for, and that the line is shown on screen as
    /// well as spoken: a secret put through here is a secret on display.
    public static var tool: [String: Any] {
        [
            "name": toolName,
            "description": """
                Say one short line out loud through Squawk, the desk pet on this \
                Mac, so the person hears it without watching the terminal. Use it \
                when something is worth looking up for: a long job starting or \
                finishing, or a question you are about to ask. Not for narration \
                and not for progress. The line is shown on screen as well as \
                spoken, so nothing secret belongs in it.
                """,
            "inputSchema": [
                "type": "object",
                "properties": [
                    "text": [
                        "type": "string",
                        "description": "One short sentence, written as it should be said out loud.",
                    ],
                ],
                "required": ["text"],
            ],
        ]
    }

    /// One JSON-RPC line in, at most one line out. A notification is answered
    /// with nothing at all: replying to one is a protocol error, and a client
    /// is entitled to close the session over it.
    public static func respond(
        to line: Data,
        version: String = "0",
        speak: (String) -> Spoken
    ) -> Data? {
        guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let method = root["method"] as? String
        else {
            return reply(id: nil, body: ["error": problem(-32700, "Not readable as JSON-RPC.")])
        }

        // A null id is not an id. Anything else is echoed back exactly as it
        // arrived, because it may be a string or a number and both are legal.
        let raw = root["id"]
        let id = raw is NSNull ? nil : raw

        switch method {
        case "initialize":
            return reply(id: id, body: ["result": [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": serverName, "version": version],
            ]])

        case "tools/list":
            return reply(id: id, body: ["result": ["tools": [tool]]])

        case "ping":
            return reply(id: id, body: ["result": [String: Any]()])

        case "tools/call":
            let params = root["params"] as? [String: Any] ?? [:]
            guard params["name"] as? String == toolName else {
                let named = params["name"] as? String ?? "nothing"
                return reply(id: id, body: [
                    "error": problem(-32602, "Squawk has one tool, \(toolName); asked for \(named)."),
                ])
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            guard let text = arguments["text"] as? String else {
                return reply(id: id, body: [
                    "error": problem(-32602, "\(toolName) needs a text argument."),
                ])
            }
            let outcome = speak(text)
            // A refusal is the tool's own result rather than a protocol error:
            // nothing went wrong with the call, the pet simply did not say it.
            return reply(id: id, body: ["result": [
                "content": [["type": "text", "text": outcome.detail]],
                "isError": !outcome.spoke,
            ]])

        default:
            // Everything else, `notifications/initialized` included, arrives
            // without an id and is answered with silence.
            guard id != nil else { return nil }
            return reply(id: id, body: [
                "error": problem(-32601, "\(method) is not something Squawk does."),
            ])
        }
    }

    private static func problem(_ code: Int, _ message: String) -> [String: Any] {
        ["code": code, "message": message]
    }

    private static func reply(id: Any?, body: [String: Any]) -> Data? {
        var payload: [String: Any] = ["jsonrpc": "2.0", "id": id ?? NSNull()]
        payload.merge(body) { _, new in new }
        guard var data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.sortedKeys]
        ) else { return nil }
        data.append(0x0A)
        return data
    }
}

/// What Claude Code's own config says about Squawk's MCP server. Read, and
/// never written.
///
/// `~/.claude.json` holds every project and every conversation Claude Code has,
/// and Claude Code rewrites it while it runs. Taking a copy, editing it and
/// writing it back would discard whatever it wrote in between, which is a
/// different bargain from the hook's `settings.json`. `claude mcp add` is the
/// supported way in, so this reports the state and prints that command.
public enum MCPRegistration {
    public static func path(home: String = NSHomeDirectory()) -> String {
        (home as NSString).appendingPathComponent(".claude.json")
    }

    public static func addCommand(binary: String) -> String {
        "claude mcp add \(MCP.serverName) -- \(binary) --mcp"
    }

    /// Matched on the command rather than on the key, because the server may be
    /// registered under any name the user chose.
    public static func status(binary: String, path configPath: String? = nil) -> InstallStatus {
        let configPath = configPath ?? path()
        guard FileManager.default.fileExists(atPath: configPath) else { return .missing }
        guard let data = FileManager.default.contents(atPath: configPath) else {
            return .invalid("could not read \(configPath)")
        }
        if data.isEmpty { return .missing }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .invalid("\(configPath) is not valid JSON")
        }
        let servers = root["mcpServers"] as? [String: Any] ?? [:]
        let ours = servers.values
            .compactMap { $0 as? [String: Any] }
            .filter { ($0["command"] as? String)?.contains("squawk-hook") == true }
        guard !ours.isEmpty else { return .missing }
        if ours.count > 1 { return .conflict(count: ours.count) }
        let command = ours[0]["command"] as? String ?? ""
        return command == binary ? .installed : .needsUpdate(existing: command)
    }
}
