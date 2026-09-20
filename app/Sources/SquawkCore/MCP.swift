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

    /// Where one registration lives and what it runs.
    public struct Registration: Sendable, Equatable {
        /// `user` for the top level, or the directory it is scoped to.
        public let scope: String
        public let command: String

        public init(scope: String, command: String) {
            self.scope = scope
            self.command = command
        }

        public var described: String {
            scope == Registration.userScope
                ? "user scope"
                : "the project at \(scope)"
        }

        public static let userScope = "user"
    }

    /// Every Squawk entry the config holds, in either scope.
    ///
    /// `claude mcp add` writes a project scoped entry by default, under
    /// `projects.<path>.mcpServers`, so reading only the top level reports a
    /// server that works perfectly well as missing. Matched on the command
    /// rather than the key, because it may be registered under any name.
    public static func registrations(
        path configPath: String? = nil
    ) throws -> [Registration] {
        let configPath = configPath ?? path()
        guard FileManager.default.fileExists(atPath: configPath) else { return [] }
        guard let data = FileManager.default.contents(atPath: configPath) else {
            throw RegistrationError.unreadable("could not read \(configPath)")
        }
        if data.isEmpty { return [] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RegistrationError.unreadable("\(configPath) is not valid JSON")
        }

        func ours(_ servers: Any?, scope: String) -> [Registration] {
            (servers as? [String: Any] ?? [:]).values
                .compactMap { $0 as? [String: Any] }
                .compactMap { $0["command"] as? String }
                .filter { $0.contains("squawk-hook") }
                .map { Registration(scope: scope, command: $0) }
        }

        var found = ours(root["mcpServers"], scope: Registration.userScope)
        for (project, settings) in root["projects"] as? [String: Any] ?? [:] {
            found += ours((settings as? [String: Any])?["mcpServers"], scope: project)
        }
        return found.sorted { $0.scope < $1.scope }
    }

    public enum RegistrationError: Error, Equatable {
        case unreadable(String)
    }

    public static func status(binary: String, path configPath: String? = nil) -> InstallStatus {
        let found: [Registration]
        do {
            found = try registrations(path: configPath)
        } catch {
            guard case RegistrationError.unreadable(let why) = error else {
                return .invalid("\(error)")
            }
            return .invalid(why)
        }
        guard !found.isEmpty else { return .missing }
        // Registered in more than one scope is not a conflict: a project entry
        // and a user entry are both meant to be there. Only the same scope
        // twice would be, and the config cannot express that.
        if let current = found.first(where: { $0.command == binary }) {
            _ = current
            return .installed
        }
        if found.count > 1 { return .conflict(count: found.count) }
        return .needsUpdate(existing: found[0].command)
    }
}
