import Foundation

/// The line protocol between `squawk-hook` and the app. Newline delimited JSON
/// over a Unix domain socket; one request, one decision, then the peer closes.
public enum Wire {
    public static let version = 1
}

/// What a blocked agent is asking permission to do.
public struct PendingRequest: Codable, Sendable, Equatable, Identifiable {
    public let v: Int
    public let id: String
    public let sessionId: String
    public let cwd: String
    public let tool: String
    public let summary: String
    public let tty: String?
    public let permissionMode: String?
    /// Seconds the hook will wait before giving up. The app expires the arc on
    /// this, because a decision made after it has nobody left to receive it.
    public let waitSeconds: Double?
    /// Parent pids, nearest first. The app resolves the owning terminal from
    /// these, because which terminal you are in decides how a pane is focused.
    public let ancestors: [Int32]?
    /// False when the session is merely waiting on you and no hook is blocked,
    /// which is what a question looks like: there is nothing to allow or deny,
    /// only somewhere to go.
    public let needsDecision: Bool?

    public init(
        v: Int = Wire.version,
        id: String,
        sessionId: String,
        cwd: String,
        tool: String,
        summary: String,
        tty: String? = nil,
        permissionMode: String? = nil,
        waitSeconds: Double? = nil,
        ancestors: [Int32]? = nil,
        needsDecision: Bool? = true
    ) {
        self.v = v
        self.id = id
        self.sessionId = sessionId
        self.cwd = cwd
        self.tool = tool
        self.summary = summary
        self.tty = tty
        self.permissionMode = permissionMode
        self.waitSeconds = waitSeconds
        self.ancestors = ancestors
        self.needsDecision = needsDecision
    }

    public var awaitsDecision: Bool { needsDecision ?? true }

    /// The label on the arc. The last path component of the working directory
    /// is what tells two concurrent sessions apart at a glance.
    public var project: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
}

public enum Decision: String, Codable, Sendable {
    case allow
    case deny
}

/// The app's reply. `reason` is surfaced to the agent when denying.
public struct DecisionReply: Codable, Sendable, Equatable {
    public let v: Int
    public let id: String
    public let decision: Decision
    public let reason: String?

    public init(v: Int = Wire.version, id: String, decision: Decision, reason: String? = nil) {
        self.v = v
        self.id = id
        self.decision = decision
        self.reason = reason
    }
}

public enum WireCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }
}
