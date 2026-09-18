import Foundation

/// The JSON a PreToolUse hook prints on stdout to settle a permission prompt.
/// Shape is fixed by Claude Code; `permissionDecisionReason` is required on deny.
public enum HookOutput {
    public static func json(for decision: Decision, reason: String? = nil) -> String {
        var specific: [String: String] = [
            "hookEventName": "PreToolUse",
            "permissionDecision": decision.rawValue,
        ]
        if decision == .deny {
            specific["permissionDecisionReason"] = reason?.isEmpty == false
                ? reason!
                : "Denied from Squawk"
        } else if let reason, !reason.isEmpty {
            specific["permissionDecisionReason"] = reason
        }

        let payload = ["hookSpecificOutput": specific]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        ), let text = String(data: data, encoding: .utf8) else {
            // Unreachable with a dictionary of strings, but a hook must never
            // print malformed JSON; staying silent falls through to the prompt.
            return ""
        }
        return text
    }
}

/// The subset of the PreToolUse stdin payload Squawk needs.
public struct HookInput: Decodable, Sendable {
    public let sessionId: String
    public let cwd: String
    public let toolName: String
    public let toolUseId: String
    public let permissionMode: String?
    public let toolInput: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case toolName = "tool_name"
        case toolUseId = "tool_use_id"
        case permissionMode = "permission_mode"
        case toolInput = "tool_input"
    }

    public init(
        sessionId: String,
        cwd: String,
        toolName: String,
        toolUseId: String,
        permissionMode: String? = nil,
        toolInput: [String: JSONValue]? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.toolName = toolName
        self.toolUseId = toolUseId
        self.permissionMode = permissionMode
        self.toolInput = toolInput
    }
}

/// Minimal JSON tree. Tool inputs are open ended, so the hook keeps them as
/// data rather than modelling every tool's schema.
public enum JSONValue: Decodable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .null
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}
