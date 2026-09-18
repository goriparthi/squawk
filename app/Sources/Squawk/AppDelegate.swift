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
    var panelIsVisible: Bool { panel?.isVisible ?? false }
    var waitingSummary: String {
        roster.isEmpty ? "Nothing waiting" : "\(roster.count) waiting"
    }
    let visibilityItem = NSMenuItem(title: "Show Dial", action: nil, keyEquivalent: "")
    let waitingItem = NSMenuItem(title: "Nothing waiting", action: nil, keyEquivalent: "")
    let dailyItem = NSMenuItem(title: "Check Daily", action: nil, keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Open at Login", action: nil, keyEquivalent: "")
    private var sweeper: Timer?
    private let hoverCard = HoverCard()
    /// Width of the painted arc band plus its breathing room.
    private let ringBand: CGFloat = 30

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

        if Settings.checksDaily, UpdateSchedule.isDue(every: 24) {
            runUpdateCheck(announceWhenCurrent: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    private func buildPanel() {
        // Square window, circular paint. The content has to live inside the
        // inner circle, so its width is that circle's inscribed square.
        let diameter: CGFloat = 320
        let inner = diameter - 2 * ringBand
        let cardWidth = (inner / 2.squareRoot()).rounded(.down)

        let panel = SquawkPanel(contentRect: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        let background = CircleBackgroundView(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        background.autoresizingMask = [.width, .height]

        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.onSelect = { [weak self] id in self?.select(id) }
        ring.onHover = { [weak self] id in self?.hover(id) }
        background.addSubview(ring)

        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.onAllow = { [weak self] in self?.settle(.allow) }
        detail.onDeny = { [weak self] in self?.settle(.deny) }
        detail.onOpenPane = { [weak self] in self?.openPane() }
        background.addSubview(detail)

        NSLayoutConstraint.activate([
            ring.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            ring.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            ring.topAnchor.constraint(equalTo: background.topAnchor),
            ring.bottomAnchor.constraint(equalTo: background.bottomAnchor),

            detail.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            detail.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            detail.widthAnchor.constraint(equalToConstant: cardWidth),
        ])

        panel.contentView = background
        // A dock belongs where you put it, so the frame is remembered. The
        // default sits clear of the menu bar and the Dock rather than centred
        // over whatever you are reading.
        panel.setFrameAutosaveName("SquawkDial")
        if panel.frame.origin == .zero, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - diameter - 24,
                y: visible.minY + 24
            ))
        }
        self.panel = panel
        render()
        panel.invalidateShadow()
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
        item.menu = buildMenu()
        statusItem = item
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        visibilityItem.target = self
        visibilityItem.action = #selector(toggle)
        menu.addItem(visibilityItem)
        menu.addItem(.separator())

        waitingItem.isEnabled = false
        menu.addItem(waitingItem)
        menu.addItem(.separator())

        menu.addItem(makeItem("Check for Updates\u{2026}", #selector(checkForUpdates)))
        dailyItem.target = self
        dailyItem.action = #selector(toggleDailyChecks)
        menu.addItem(dailyItem)
        loginItem.target = self
        loginItem.action = #selector(toggleLoginItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())

        menu.addItem(makeItem("Squawk on GitHub", #selector(openRepo)))
        menu.addItem(makeItem("Report an Issue", #selector(openIssues)))
        menu.addItem(makeItem("About Squawk", #selector(showAbout)))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Squawk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        return menu
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
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
        guard let id = ring.selectedID, let entry = roster.entry(id: id) else { return }
        PaneOpener.focus(entry.request)
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

    /// The circle only has room for a truncated command, so the full text is
    /// shown beside it while the pointer is on an arc.
    private func hover(_ id: String?) {
        guard let id, let entry = roster.entry(id: id), let panel else {
            hoverCard.hide()
            return
        }
        hoverCard.show(entry.request, besides: panel)
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
        detail.show(selected, waiting: roster.count)
        panel?.invalidateShadow()
        statusItem?.button?.title = roster.isEmpty ? "" : " \(roster.count)"
        waitingItem.title = roster.isEmpty
            ? "Nothing waiting"
            : "\(roster.count) waiting"
        visibilityItem.title = (panel?.isVisible ?? false) ? "Hide Dial" : "Show Dial"
    }

    private func show() {
        panel?.orderFrontRegardless()
    }

    private func hide() {
        hoverCard.hide()
        panel?.orderOut(nil)
    }

    @objc private func toggle() {
        guard let panel else { return }
        if panel.isVisible { hide() } else { show() }
    }
}

// MARK: - Menu actions

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        dailyItem.state = Settings.checksDaily ? .on : .off
        loginItem.state = LoginItem.isEnabled ? .on : .off
        visibilityItem.title = (panelIsVisible) ? "Hide Dial" : "Show Dial"
        waitingItem.title = waitingSummary
    }
}

extension AppDelegate {
    @objc func toggleDailyChecks() {
        Settings.checksDaily.toggle()
        if Settings.checksDaily { runUpdateCheck(announceWhenCurrent: false) }
    }

    @objc func toggleLoginItem() {
        let wanted = !LoginItem.isEnabled
        if let message = LoginItem.set(wanted) {
            present(title: "Open at Login", message: message)
        }
    }

    @objc func checkForUpdates() {
        runUpdateCheck(announceWhenCurrent: true)
    }

    @objc func openRepo() { NSWorkspace.shared.open(Updates.repoURL) }
    @objc func openIssues() { NSWorkspace.shared.open(Updates.issuesURL) }

    @objc func showAbout() {
        present(
            title: "Squawk \(Updates.bundleVersion)",
            message: """
            A floating dial for approving what your coding agents want to do, \
            without switching to the terminal.

            \(LoginItem.statusDescription)
            """
        )
    }

    /// The daily check is opt in and silent unless there is something to say, so
    /// opening a laptop never greets you with a dialog you did not ask for.
    func runUpdateCheck(announceWhenCurrent: Bool) {
        Updates.check { outcome in
            Task { @MainActor in
                switch outcome {
                case .available(let version, let page, let asset):
                    self.offerUpdate(version: version, page: page, asset: asset)
                case .upToDate(let version):
                    guard announceWhenCurrent else { return }
                    self.present(title: "Up to date", message: "Squawk \(version) is the latest release.")
                case .failed(let message):
                    guard announceWhenCurrent else { return }
                    self.present(title: "Check for Updates", message: message)
                }
            }
        }
    }

    private func offerUpdate(version: String, page: URL, asset: URL?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Squawk \(version) is available"
        alert.informativeText = "You are running \(Updates.bundleVersion)."
        alert.addButton(withTitle: asset == nil ? "Open Release" : "Download")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(asset ?? page)
        }
    }

    func present(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
