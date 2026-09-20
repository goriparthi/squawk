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

/// The enclosing app's version, for the MCP handshake. The hook lives at
/// `Contents/Helpers/squawk-hook`, so `Bundle.main` is the bare executable and
/// carries no Info.plist; a build outside a bundle has none at all.
func bundledVersion() -> String {
    let helpers = (CommandLine.arguments[0] as NSString).deletingLastPathComponent
    let contents = ((helpers as NSString).deletingLastPathComponent as NSString)
    let plist = contents.appendingPathComponent("Info.plist")
    guard let data = FileManager.default.contents(atPath: plist),
          let root = try? PropertyListSerialization.propertyList(from: data, format: nil)
            as? [String: Any],
          let version = root["CFBundleShortVersionString"] as? String
    else { return "0" }
    return version
}

// Self install, so a DMG user can register the hook without a checkout.
let argv = Array(CommandLine.arguments.dropFirst())
let arguments = Set(argv)

// What each agent's config says right now, without changing anything. A stale
// path is the failure that looks most like the app being broken.
if arguments.contains("--status") {
    let binary = CommandLine.arguments[0].hasPrefix("/")
        ? CommandLine.arguments[0]
        : FileManager.default.currentDirectoryPath + "/" + CommandLine.arguments[0]
    var allGood = true
    for host in AgentHost.allCases {
        let status = HookInstaller.status(binary: binary, host: host)
        print("\(host.displayName): \(status.summary)")
        print("  \(host.settingsPath())")
        if status.needsAction { allGood = false }
    }
    print("\nthis binary: \(binary)")
    exit(allGood ? 0 : 1)
}

// Whether the MCP server is registered, and how to register it. Read only on
// purpose: `~/.claude.json` is rewritten by Claude Code while it runs, so
// editing a copy of it would discard whatever it wrote in the meantime.
if arguments.contains("--mcp-status") {
    let binary = CommandLine.arguments[0].hasPrefix("/")
        ? CommandLine.arguments[0]
        : FileManager.default.currentDirectoryPath + "/" + CommandLine.arguments[0]
    let status = MCPRegistration.status(binary: binary)
    print("MCP speak tool: \(status.summary)")
    print("  \(MCPRegistration.path())")
    // Named, because `claude mcp add` scopes to the project by default and a
    // server registered in one project looks absent from every other one.
    for entry in (try? MCPRegistration.registrations()) ?? [] {
        print("  in \(entry.described): \(entry.command)")
    }
    if status.needsAction {
        print("\nregister it with:")
        print("  \(MCPRegistration.addCommand(binary: binary))")
    }
    print("\nthis binary: \(binary)")
    exit(status.needsAction ? 1 : 0)
}

if arguments.contains("--install") || arguments.contains("--uninstall") {
    let installing = arguments.contains("--install")
    let binary = CommandLine.arguments[0].hasPrefix("/")
        ? CommandLine.arguments[0]
        : FileManager.default.currentDirectoryPath + "/" + CommandLine.arguments[0]

    // NSHomeDirectory reads the password database, not $HOME, so an override is
    // the only way to point this somewhere else. Tests need it; so does anyone
    // keeping settings outside the default location.
    let override = argv.firstIndex(of: "--settings").flatMap { index -> String? in
        index + 1 < argv.count ? argv[index + 1] : nil
    }

    // Both agents share the PreToolUse contract, so one binary serves both. By
    // default it registers with whichever is actually present on the machine.
    let requested: [AgentHost] = {
        var picked: [AgentHost] = []
        if arguments.contains("--claude") { picked.append(.claudeCode) }
        if arguments.contains("--codex") { picked.append(.codex) }
        if !picked.isEmpty { return picked }
        if override != nil { return [.claudeCode] }
        let present = AgentHost.allCases.filter {
            FileManager.default.fileExists(
                atPath: ($0.settingsPath() as NSString).deletingLastPathComponent
            )
        }
        return present.isEmpty ? [.claudeCode] : present
    }()

    var failed = false
    for host in requested {
        let settings = override ?? host.settingsPath()
        switch HookInstaller.apply(
            install: installing, binary: binary, host: host, settings: settings
        ) {
        case .installed(let path):
            print("\(host.displayName): registered on \(host.decisionEvent) in \(settings)")
            print("  \(path)")
        case .removed:
            print("\(host.displayName): hook removed from \(settings)")
        case .failed(let message):
            FileHandle.standardError.write(Data(("\(host.displayName): \(message)\n").utf8))
            failed = true
        }
    }
    exit(failed ? 1 : 0)
}

// MCP server. A long lived stdio session rather than one shot: the agent
// spawns this once and calls `speak` through it for as long as it runs.
//
// Nothing but JSON-RPC may ever reach stdout in this mode. A stray print is not
// a cosmetic problem, it corrupts the transport and the client drops the server.
if arguments.contains("--mcp") {
    let socketPath = ProcessInfo.processInfo.environment["SQUAWK_SOCKET"]
        ?? SocketPath.defaultSocket

    // The app decides whether a line is said, how often, and what is redacted
    // out of it. This end only carries the question and the answer.
    func askAppToSpeak(_ text: String) -> MCP.Spoken {
        let silent = "Squawk is not running, so nothing was said."
        guard FileManager.default.fileExists(atPath: socketPath) else {
            return MCP.Spoken(spoke: false, detail: silent)
        }
        let ask = SpeakRequest(text: text, cwd: FileManager.default.currentDirectoryPath)
        guard let payload = try? WireCodec.encode(ask),
              let fd = try? UnixSocket.connect(to: socketPath, timeout: 2)
        else { return MCP.Spoken(spoke: false, detail: silent) }
        defer { close(fd) }
        // Short, because the app answers this itself. Nothing on this path ever
        // waits for a human, which is what keeps an agent from blocking on it.
        UnixSocket.setTimeout(fd, SO_RCVTIMEO, 3)
        guard (try? UnixSocket.writeAll(fd, payload)) != nil,
              let line = try? UnixSocket.readLine(fd),
              let reply = try? WireCodec.decode(SpeakReply.self, from: line)
        else { return MCP.Spoken(spoke: false, detail: "Squawk did not answer, so nothing was said.") }
        return MCP.Spoken(spoke: reply.spoke, detail: reply.detail)
    }

    while let text = readLine(strippingNewline: true) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
        guard let out = MCP.respond(
            to: Data(text.utf8), version: bundledVersion(), speak: askAppToSpeak
        ) else { continue }
        FileHandle.standardOutput.write(out)
    }
    exit(0)
}

let stdinData = FileHandle.standardInput.readDataToEndOfFile()

// Notification mode. The agent wants the human but nothing is blocked, so this
// posts the session to the dial and returns immediately. A question cannot be
// answered from the dial, but it can at least stop being invisible.
if arguments.contains("--notify") {
    guard !stdinData.isEmpty,
          let note = try? JSONDecoder().decode(NotificationInput.self, from: stdinData)
    else { failOpen() }

    let socketPath = ProcessInfo.processInfo.environment["SQUAWK_SOCKET"] ?? SocketPath.defaultSocket
    guard FileManager.default.fileExists(atPath: socketPath) else { failOpen() }

    let request = PendingRequest(
        // Keyed by session, so repeated notifications replace rather than stack.
        id: "notify:" + note.sessionId,
        sessionId: note.sessionId,
        cwd: note.cwd ?? FileManager.default.currentDirectoryPath,
        tool: note.notificationType ?? "Waiting",
        summary: ToolSummary.sanitize(note.message ?? "Waiting for you"),
        tty: TTY.current(),
        permissionMode: nil,
        waitSeconds: 300,
        ancestors: ProcessTree.ancestors(),
        needsDecision: false
    )
    if let payload = try? WireCodec.encode(request),
       let fd = try? UnixSocket.connect(to: socketPath, timeout: 2) {
        try? UnixSocket.writeAll(fd, payload)
        close(fd)
    }
    exit(0)
}

guard !stdinData.isEmpty,
      let input = try? JSONDecoder().decode(HookInput.self, from: stdinData)
else { failOpen() }

// PreToolUse runs before Claude Code decides whether it would even ask, so
// gating every mode turns silent auto-approval into a dial prompt for calls that
// would never have stopped. PermissionRequest is already the moment of asking,
// so it is never filtered.
let event = input.event
if event.respectsGatePolicy {
    let gateModes = GatePolicy.modes(from: ProcessInfo.processInfo.environment["SQUAWK_GATE_MODES"])
    guard GatePolicy.shouldGate(mode: input.permissionMode, allowed: gateModes) else {
        failOpen()
    }
}

let socketPath = ProcessInfo.processInfo.environment["SQUAWK_SOCKET"] ?? SocketPath.defaultSocket
guard FileManager.default.fileExists(atPath: socketPath) else { failOpen() }

let budget = waitBudget()

let request = PendingRequest(
    id: input.requestId,
    sessionId: input.sessionId,
    cwd: input.cwd,
    tool: input.toolName,
    summary: ToolSummary.describe(tool: input.toolName, input: input.toolInput, cwd: input.cwd),
    tty: TTY.current(),
    permissionMode: input.permissionMode,
    waitSeconds: budget,
    ancestors: ProcessTree.ancestors()
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

let output = HookOutput.json(for: reply.decision, reason: reply.reason, event: event)
guard !output.isEmpty else { failOpen() }
print(output)
exit(0)
