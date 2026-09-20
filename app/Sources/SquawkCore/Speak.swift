import Foundation

/// A line an agent asked the pet to say, through the MCP `speak` tool. It rides
/// the same socket and the same newline delimited framing as a decision; `kind`
/// is what tells the two apart, and a decision frame carries none.
public struct SpeakRequest: Codable, Sendable, Equatable {
    public static let frameKind = "speak"

    public let v: Int
    public let kind: String
    public let text: String
    /// Where the agent was working. For the record only: nothing an agent sends
    /// here may decide anything, which is the whole rule of this path.
    public let cwd: String?

    public init(v: Int = Wire.version, text: String, cwd: String? = nil) {
        self.v = v
        self.kind = Self.frameKind
        self.text = text
        self.cwd = cwd
    }

    /// The label a spoken line is filed under in the week, the same way a
    /// request is: the directory is what tells two agents apart at a glance.
    public var project: String? {
        guard let cwd, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }
}

/// Whether the pet said it, and if not, why. An agent told nothing reports
/// success for a line that nobody heard.
public struct SpeakReply: Codable, Sendable, Equatable {
    public let v: Int
    public let kind: String
    public let spoke: Bool
    public let detail: String

    public init(v: Int = Wire.version, spoke: Bool, detail: String) {
        self.v = v
        self.kind = SpeakRequest.frameKind
        self.spoke = spoke
        self.detail = detail
    }
}

/// What arrived on the socket.
public enum WireFrame: Sendable, Equatable {
    case decision(PendingRequest)
    case speak(SpeakRequest)
}

private struct FrameMarker: Decodable {
    let kind: String?
}

extension WireCodec {
    /// Which sort of frame this is. A decision carries no `kind` at all, so the
    /// absence is the answer and a hook from an older build still reads as one.
    public static func frame(from data: Data) throws -> WireFrame {
        let marker = try? JSONDecoder().decode(FrameMarker.self, from: data)
        if marker?.kind == SpeakRequest.frameKind {
            return .speak(try decode(SpeakRequest.self, from: data))
        }
        return .decision(try decode(PendingRequest.self, from: data))
    }
}

/// What an agent is allowed to put in the pet's mouth.
///
/// A tool that lets an agent speak is a tool that lets a prompt injection
/// speak, so every line is redacted and the rate is capped before anything is
/// said. The app keeps the one gate, because the pet has one mouth: a limit
/// held by each client would be as many limits as there are agents running.
public struct SpeakGate: Sendable, Equatable {
    /// Six a minute is a line every ten seconds, which is more than anything
    /// worth interrupting someone for and far less than a loop.
    public static let mostPerMinute = 6
    /// A neural line takes about two and a half seconds to start, so anything
    /// closer than this would replace a line nobody has heard yet.
    public static let leastGap: TimeInterval = 2
    /// The bubble's own limit. Longer than this is a paragraph rather than
    /// something said out loud.
    public static let longest = DialGeometry.bubbleTextLimit

    public enum Verdict: Sendable, Equatable {
        /// Redacted, trimmed, and ready to say.
        case say(String)
        /// Not said, and why, in a line handed straight back to the agent.
        case refused(String)
    }

    /// When each admitted line was let through, inside the last minute.
    private var spokenAt: [Date] = []

    public init() {}

    public mutating func admit(_ text: String, at now: Date = Date()) -> Verdict {
        // Redacted before it is drawn or spoken. The pet sits on screen during
        // screen shares, and a token read out loud is a token published.
        let line = ToolSummary.sanitize(ToolSummary.redact(text), to: Self.longest)
        guard !line.isEmpty else { return .refused("There was nothing to say.") }

        spokenAt.removeAll { now.timeIntervalSince($0) > 60 }
        if let last = spokenAt.last, now.timeIntervalSince(last) < Self.leastGap {
            return .refused("Squawk is still saying the last line. Try again in a moment.")
        }
        if spokenAt.count >= Self.mostPerMinute {
            return .refused("Squawk says at most \(Self.mostPerMinute) lines a minute.")
        }
        spokenAt.append(now)
        return .say(line)
    }
}
