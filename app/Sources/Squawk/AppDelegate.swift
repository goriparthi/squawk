import AppKit
import SquawkCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: SquawkPanel?
    private let ring = RingView()
    private let detail = DetailView()
    private var server: RequestServer?
    private var roster = Roster()
    private var replies: [String: @Sendable (DecisionReply) -> Void] = [:]
    private var statusItem: NSStatusItem?
    private var sweeper: Timer?

    /// Only for a request that predates `waitSeconds` on the wire. Current hooks
    /// declare their own budget and the roster expires each arc on that.
    private let fallbackLifetime: TimeInterval = 120

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildPanel()
        buildStatusItem()
        startServer()

        sweeper = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sweep() }
        }

        // Design review: the panel is normally only raised by a waiting request,
        // so the cleared state is otherwise impossible to look at.
        if CommandLine.arguments.contains("--preview-empty") { show() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    private func buildPanel() {
        let width: CGFloat = 300
        let height: CGFloat = 372
        let panel = SquawkPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height))

        let background = PanelBackgroundView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        background.autoresizingMask = [.width, .height]

        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.onSelect = { [weak self] id in self?.select(id) }

        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.onAllow = { [weak self] in self?.settle(.allow) }
        detail.onDeny = { [weak self] in self?.settle(.deny) }
        detail.onOpenPane = { [weak self] in self?.openPane() }

        // The ring and the card are one column, centred as a group. Pinning the
        // ring to the top left it clipped by the rounded corner, and left the
        // cleared state with all its slack below the circle instead of around it.
        let column = NSStackView(views: [ring, detail])
        column.orientation = .vertical
        column.alignment = .centerX
        column.spacing = 20
        column.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(column)

        NSLayoutConstraint.activate([
            column.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            column.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            column.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 20),
            column.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -20),
            column.topAnchor.constraint(greaterThanOrEqualTo: background.topAnchor, constant: 22),

            ring.widthAnchor.constraint(equalToConstant: 196),
            ring.heightAnchor.constraint(equalTo: ring.widthAnchor),
            detail.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])

        panel.contentView = background
        panel.center()
        self.panel = panel
        render()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A template image so macOS tints it for the menu bar's appearance. The
        // brand kit is explicit that the full colour icon never goes up here.
        if let url = Bundle.main.url(forResource: "StatusTemplate", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            item.button?.image = image
            item.button?.imagePosition = .imageLeading
        } else {
            item.button?.title = "Squawk"
        }
        item.button?.target = self
        item.button?.action = #selector(toggle)
        statusItem = item
    }

    private func startServer() {
        let path = ProcessInfo.processInfo.environment["SQUAWK_SOCKET"] ?? SocketPath.defaultSocket
        let server = RequestServer(path: path) { [weak self] request, reply in
            Task { @MainActor in self?.accept(request, reply: reply) }
        }
        do {
            try server.start()
            self.server = server
        } catch {
            NSLog("squawk: cannot listen on %@: %@", path, String(describing: error))
        }
    }

    private func accept(_ request: PendingRequest, reply: @escaping @Sendable (DecisionReply) -> Void) {
        replies[request.id] = reply
        roster.add(request)
        if ring.selectedID == nil { ring.selectedID = request.id }
        render()
        show()
    }

    private func settle(_ decision: Decision) {
        guard let id = ring.selectedID else { return }
        finish(id: id, decision: decision, reason: decision == .deny ? "Denied from Squawk" : nil)
    }

    private func finish(id: String, decision: Decision, reason: String?) {
        if let reply = replies.removeValue(forKey: id) {
            reply(DecisionReply(id: id, decision: decision, reason: reason))
        }
        roster.remove(id: id)
        ring.selectedID = roster.entries.first?.id
        render()
        if roster.isEmpty { hide() }
    }

    private func openPane() {
        guard let id = ring.selectedID,
              let entry = roster.entry(id: id),
              let tty = entry.request.tty
        else { return }
        PaneOpener.focus(tty: tty)
    }

    /// Entries the hook has already abandoned. Dropping the callback is correct:
    /// the hook timed out, so nothing is listening for the reply any more.
    private func sweep() {
        let expired = roster.expire(fallback: fallbackLifetime)
        guard !expired.isEmpty else { return }
        for entry in expired { replies.removeValue(forKey: entry.id) }
        ring.selectedID = roster.entries.first?.id
        render()
        if roster.isEmpty { hide() }
    }

    private func select(_ id: String) {
        ring.selectedID = id
        render()
    }

    private func render() {
        ring.roster = roster
        let selected = ring.selectedID.flatMap { roster.entry(id: $0) }
        // Nothing waiting means nothing to act on, so the card collapses and the
        // dial is left alone in the middle rather than sat above three dead buttons.
        detail.isHidden = selected == nil
        detail.show(selected)
        statusItem?.button?.title = roster.isEmpty ? "" : " \(roster.count)"
    }

    private func show() {
        panel?.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    @objc private func toggle() {
        guard let panel else { return }
        if panel.isVisible { hide() } else { show() }
    }
}
