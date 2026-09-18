import Foundation
import SquawkCore

// PreToolUse hook. Hands the pending call to the Squawk panel and prints the
// decision it gets back. Every failure path exits silently so the terminal
// prompt still happens: Squawk may be closed, and an agent must never be stuck
// on a UI that is not running.

let defaultWait: TimeInterval = 120

func waitBudget() -> TimeInterval {
    guard let raw = ProcessInfo.processInfo.environment["SQUAWK_WAIT"],
          let value = TimeInterval(raw), value > 0
    else { return defaultWait }
    return min(value, 540)
}

func failOpen() -> Never {
    exit(0)
}

let stdinData = FileHandle.standardInput.readDataToEndOfFile()
guard !stdinData.isEmpty,
      let input = try? JSONDecoder().decode(HookInput.self, from: stdinData)
else { failOpen() }

// Nothing to ask about when the session already runs without prompting.
if let mode = input.permissionMode, mode == "bypassPermissions" {
    failOpen()
}

let socketPath = ProcessInfo.processInfo.environment["SQUAWK_SOCKET"] ?? SocketPath.defaultSocket
guard FileManager.default.fileExists(atPath: socketPath) else { failOpen() }

let budget = waitBudget()

let request = PendingRequest(
    id: input.toolUseId,
    sessionId: input.sessionId,
    cwd: input.cwd,
    tool: input.toolName,
    summary: ToolSummary.describe(tool: input.toolName, input: input.toolInput, cwd: input.cwd),
    tty: TTY.current(),
    permissionMode: input.permissionMode,
    waitSeconds: budget
)

guard let payload = try? WireCodec.encode(request) else { failOpen() }

guard let fd = try? UnixSocket.connect(to: socketPath, timeout: 2) else { failOpen() }
defer { close(fd) }

// The connect deadline is short so a dead socket is cheap; the reply deadline is
// the human's thinking time.
UnixSocket.setTimeout(fd, SO_RCVTIMEO, budget)

guard (try? UnixSocket.writeAll(fd, payload)) != nil,
      let line = try? UnixSocket.readLine(fd),
      let reply = try? WireCodec.decode(DecisionReply.self, from: line),
      reply.id == request.id
else { failOpen() }

let output = HookOutput.json(for: reply.decision, reason: reply.reason)
guard !output.isEmpty else { failOpen() }
print(output)
exit(0)
