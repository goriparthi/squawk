import Foundation

/// Which event Squawk is answering. The two agents publish the same input field
/// names but different reply shapes, so the event decides how a decision is written.
public enum AgentEvent: String, Sendable, CaseIterable {
    /// Claude Code, fired before every tool call.
    case preToolUse = "PreToolUse"
    /// Codex, fired only when Codex is about to ask. No gating decision needed:
    /// if it fires at all, the human was going to be asked.
    case permissionRequest = "PermissionRequest"

    public static func named(_ raw: String?) -> AgentEvent {
        guard let raw, let event = AgentEvent(rawValue: raw) else { return .preToolUse }
        return event
    }

    /// PermissionRequest only fires when the agent would have prompted, so it is
    /// never filtered by permission mode.
    public var respectsGatePolicy: Bool { self == .preToolUse }
}

/// The JSON a hook prints on stdout to settle a permission prompt. Both shapes
/// are fixed by their agent and they are not the same: Claude Code takes a flat
/// `permissionDecision`, Codex takes a nested `decision.behavior`.
public enum HookOutput {
    public static func json(
        for decision: Decision,
        reason: String? = nil,
        event: AgentEvent = .preToolUse
    ) -> String {
        let payload: [String: Any]
        switch event {
        case .preToolUse:
            var specific: [String: String] = [
                "hookEventName": event.rawValue,
                "permissionDecision": decision.rawValue,
            ]
            if decision == .deny {
                specific["permissionDecisionReason"] = reason?.isEmpty == false
                    ? reason!
                    : "Denied from Squawk"
            } else if let reason, !reason.isEmpty {
                specific["permissionDecisionReason"] = reason
            }
            payload = ["hookSpecificOutput": specific]

        case .permissionRequest:
            var inner: [String: String] = ["behavior": decision.rawValue]
            if decision == .deny {
                inner["message"] = reason?.isEmpty == false ? reason! : "Denied from Squawk"
            }
            payload = ["hookSpecificOutput": [
                "hookEventName": event.rawValue,
                "decision": inner,
            ]]
        }
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

/// The subset of the Notification stdin payload Squawk needs. Fired when the
/// agent wants the human: a question, an idle prompt, a permission dialog.
public struct NotificationInput: Decodable, Sendable {
    public let sessionId: String
    public let cwd: String?
    public let message: String?
    public let notificationType: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case message
        case notificationType = "notification_type"
    }
}

/// The subset of the stdin payload Squawk needs. Claude Code and Codex agree on
/// these field names; Codex carries `turn_id` and no `tool_use_id`, so the id is
/// optional and falls back rather than failing the whole decode.
public struct HookInput: Decodable, Sendable {
    public let sessionId: String
    public let cwd: String
    public let toolName: String
    public let toolUseId: String?
    public let turnId: String?
    public let hookEventName: String?
    public let permissionMode: String?
    public let toolInput: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case toolName = "tool_name"
        case toolUseId = "tool_use_id"
        case turnId = "turn_id"
        case hookEventName = "hook_event_name"
        case permissionMode = "permission_mode"
        case toolInput = "tool_input"
    }

    public init(
        sessionId: String,
        cwd: String,
        toolName: String,
        toolUseId: String? = nil,
        turnId: String? = nil,
        hookEventName: String? = nil,
        permissionMode: String? = nil,
        toolInput: [String: JSONValue]? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.toolName = toolName
        self.toolUseId = toolUseId
        self.turnId = turnId
        self.hookEventName = hookEventName
        self.permissionMode = permissionMode
        self.toolInput = toolInput
    }

    public var event: AgentEvent { AgentEvent.named(hookEventName) }

    /// Something stable to key the arc on. Codex sends a turn, not a tool call.
    public var requestId: String {
        toolUseId ?? turnId.map { "turn:" + $0 } ?? "\(sessionId):\(toolName)"
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
