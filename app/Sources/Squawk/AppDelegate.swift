import AppKit
import SquawkCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: SquawkPanel?
    private let ring = RingView()
    private let detail = DetailView()
    var server: RequestServer?
    private var roster = Roster()
    private var replies: [String: @Sendable (DecisionReply) -> Void] = [:]
    private var statusItem: NSStatusItem?
    var panelIsVisible: Bool { panel?.isVisible ?? false }
    var currentSizeName: String { DialSize.nearest(to: diameter).rawValue }
    var waitingSummary: String {
        roster.isEmpty ? "Nothing waiting" : "\(roster.count) waiting"
    }
    let visibilityItem = NSMenuItem(title: "Show Dial", action: nil, keyEquivalent: "")
    let waitingItem = NSMenuItem(title: "Nothing waiting", action: nil, keyEquivalent: "")
    let dailyItem = NSMenuItem(title: "Check Daily", action: nil, keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Open at Login", action: nil, keyEquivalent: "")
    let alwaysItem = NSMenuItem(title: "Always Show Dial", action: nil, keyEquivalent: "")
    let homeItem = NSMenuItem(title: "Squawk", action: nil, keyEquivalent: "")
    var sizeItems: [NSMenuItem] = []
    /// Both glyphs are built once; rebuilding them on every render flickers.
    private var glyphCache: [Bool: NSImage] = [:]
    private var pointerInside = false
    private var updateFinished = false
    private var opacityControl: SliderRow?
    private var sizeControl: SliderRow?
    private var sweeper: Timer?
    private let hoverCard = HoverCard()
    private var diameter = Settings.diameter
    private var cardWidthConstraint: NSLayoutConstraint?

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
        if Settings.alwaysVisible || CommandLine.arguments.contains("--preview-empty") {
            show()
        }

        if Settings.checksDaily, UpdateSchedule.isDue(every: 24) {
            runUpdateCheck(announceWhenCurrent: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        flushSettings()
        server?.stop()
    }

    private func buildPanel() {
        // Square window, circular paint. The content has to live inside the
        // inner circle, so its width is that circle's inscribed square.
        let panel = SquawkPanel(contentRect: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        let background = CircleBackgroundView(frame: NSRect(x: 0, y: 0, width: diameter, height: diameter))
        background.autoresizingMask = [.width, .height]

        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.diameter = diameter
        ring.onSelect = { [weak self] id in self?.select(id) }
        ring.onHover = { [weak self] id in self?.hover(id) }
        ring.onMouseInside = { [weak self] inside in self?.setSolid(inside) }
        background.addSubview(ring)

        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.onAllow = { [weak self] in self?.settle(.allow) }
        detail.onDeny = { [weak self] in self?.settle(.deny) }
        detail.onOpenPane = { [weak self] in self?.openPane() }
        background.addSubview(detail)

        let cardWidth = detail.widthAnchor.constraint(equalToConstant: DialGeometry.cardWidth(diameter))
        cardWidthConstraint = cardWidth

        NSLayoutConstraint.activate([
            ring.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            ring.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            ring.topAnchor.constraint(equalTo: background.topAnchor),
            ring.bottomAnchor.constraint(equalTo: background.bottomAnchor),

            detail.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            detail.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            cardWidth,
        ])

        panel.contentView = background
        // A dock belongs where you put it, so the frame is remembered. The
        // default sits clear of the menu bar and the Dock rather than centred
        // over whatever you are reading.
        // Restores where it was left. The saved frame also carries the size it
        // had then, so the stored preference is reapplied about the same centre
        // rather than letting a stale frame decide how big the dial is.
        let restored = panel.setFrameUsingName("SquawkDial")
        panel.setFrameAutosaveName("SquawkDial")
        if restored {
            let centre = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
            panel.setContentSize(NSSize(width: diameter, height: diameter))
            panel.setFrameOrigin(NSPoint(
                x: (centre.x - diameter / 2).rounded(),
                y: (centre.y - diameter / 2).rounded()
            ))
            panel.setFrame(Self.nudgedOnScreen(panel.frame), display: false)
        } else if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - diameter - 24,
                y: visible.minY + 24
            ))
        }
        panel.saveFrame(usingName: "SquawkDial")
        panel.alphaValue = Settings.opacity
        self.panel = panel
        render()
        panel.invalidateShadow()
    }

    /// Grows or shrinks in place, keeping the dial's centre where the user put
    /// it rather than pinning a corner and appearing to drift.
    func applyDiameter(_ requested: CGFloat) {
        let next = DialGeometry.clamp(requested)
        guard next != diameter, let panel else { return }
        diameter = next
        Settings.diameter = next
        flushSettings()

        let centre = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        ring.diameter = next
        cardWidthConstraint?.constant = DialGeometry.cardWidth(next)
        panel.setContentSize(NSSize(width: next, height: next))
        panel.setFrameOrigin(NSPoint(
            x: (centre.x - next / 2).rounded(),
            y: (centre.y - next / 2).rounded()
        ))
        panel.setFrame(Self.nudgedOnScreen(panel.frame), display: true)
        panel.saveFrame(usingName: "SquawkDial")
        panel.contentView?.needsDisplay = true
        panel.invalidateShadow()
        sizeControl?.value = Double(next)
    }

    /// A dial restored onto a display that is no longer there, or grown past the
    /// screen edge, would be unreachable. Pull it back into the visible frame.
    static func nudgedOnScreen(_ frame: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return frame }
        var result = frame
        result.origin.x = min(max(result.origin.x, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.origin.y, visible.minY), visible.maxY - result.height)
        return result
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = statusImage(attention: false)
        item.button?.imagePosition = .imageLeading
        if item.button?.image == nil { item.button?.title = "Squawk" }
        item.menu = buildMenu()
        statusItem = item
    }

    /// A template image normally, so macOS tints it for the menu bar's
    /// appearance. When an agent is waiting it switches to the brand amber, the
    /// same colour as the arcs, so the bar says "you" without being read.
    private func statusImage(attention: Bool) -> NSImage? {
        if let cached = glyphCache[attention] { return cached }
        guard let url = Bundle.main.url(forResource: "StatusTemplate", withExtension: "png"),
              let base = NSImage(contentsOf: url)
        else { return nil }
        base.size = NSSize(width: 18, height: 18)

        let image: NSImage
        if attention {
            let amber = NSImage(size: base.size, flipped: false) { rect in
                base.draw(in: rect)
                Palette.waiting.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            amber.isTemplate = false
            image = amber
        } else {
            base.isTemplate = true
            image = base
        }
        glyphCache[attention] = image
        return image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        visibilityItem.target = self
        visibilityItem.action = #selector(toggle)
        menu.addItem(visibilityItem)
        alwaysItem.target = self
        alwaysItem.image = Self.symbol("pin")
        alwaysItem.action = #selector(toggleAlwaysVisible)
        menu.addItem(alwaysItem)
        menu.addItem(.separator())

        waitingItem.isEnabled = false
        waitingItem.image = Self.symbol("clock", colour: Palette.waiting)
        menu.addItem(waitingItem)
        menu.addItem(.separator())

        let sizeParent = NSMenuItem(title: "Size Presets", action: nil, keyEquivalent: "")
        sizeParent.image = Self.symbol("circle.circle")
        let sizes = NSMenu()
        let glyphs = ["smallcircle.filled.circle", "circle.circle", "largecircle.fill.circle"]
        for (index, size) in DialSize.allCases.enumerated() {
            let item = NSMenuItem(title: size.title, action: #selector(pickSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            item.image = Self.symbol(glyphs[index])
            sizes.addItem(item)
            sizeItems.append(item)
        }
        sizeParent.submenu = sizes

        let size = SliderRow(
            title: "Dial Size",
            value: Double(diameter),
            range: Double(DialGeometry.range.lowerBound)...Double(DialGeometry.range.upperBound),
            format: { "\(Int($0.rounded())) pt" }
        )
        size.onChange = { [weak self] value in self?.applyDiameter(CGFloat(value)) }
        let sizeItem = NSMenuItem()
        sizeItem.view = size
        menu.addItem(sizeItem)
        menu.addItem(sizeParent)
        sizeControl = size

        let opacity = SliderRow(
            title: "Opacity",
            value: Settings.opacity,
            range: DialOpacity.range,
            format: { "\(Int(($0 * 100).rounded()))%" }
        )
        opacity.onChange = { [weak self] value in self?.applyOpacity(value) }
        let opacityItem = NSMenuItem()
        opacityItem.view = opacity
        menu.addItem(opacityItem)
        opacityControl = opacity
        menu.addItem(.separator())

        menu.addItem(makeItem("Check for Updates\u{2026}", #selector(checkForUpdates),
                              symbol: "arrow.triangle.2.circlepath"))
        dailyItem.target = self
        dailyItem.image = Self.symbol("calendar")
        dailyItem.action = #selector(toggleDailyChecks)
        menu.addItem(dailyItem)
        loginItem.target = self
        loginItem.image = Self.symbol("person.badge.key")
        loginItem.action = #selector(toggleLoginItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())

        // The project page, carrying the running version. Drawn as a link so it
        // reads as somewhere to go rather than a label.
        homeItem.target = self
        homeItem.action = #selector(openProject)
        homeItem.attributedTitle = NSAttributedString(
            string: "Squawk \(Updates.bundleVersion)",
            attributes: [
                .foregroundColor: Palette.brand,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: NSFont.menuFont(ofSize: 0),
            ]
        )
        homeItem.image = Glyphs.github ?? Self.symbol("globe", colour: Palette.brand)
        homeItem.toolTip = Updates.repoURL.absoluteString
        menu.addItem(homeItem)
        menu.addItem(.separator())

        menu.addItem(makeItem("Uninstall Squawk\u{2026}", #selector(uninstall), symbol: "trash"))
        let quit = NSMenuItem(title: "Quit Squawk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = Self.symbol("power")
        menu.addItem(quit)
        return menu
    }

    private func makeItem(_ title: String, _ action: Selector, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = Self.symbol(symbol)
        return item
    }

    /// SF Symbols, sized to match the menu's text. A missing symbol name gives
    /// nil rather than a placeholder box, so the row simply has no icon.
    static func symbol(_ name: String?, colour: NSColor? = nil) -> NSImage? {
        guard let name,
              let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        else { return nil }
        let configured = image.withSymbolConfiguration(
            .init(pointSize: 13, weight: .regular)
        ) ?? image
        guard let colour else {
            configured.isTemplate = true
            return configured
        }
        let tinted = NSImage(size: configured.size, flipped: false) { rect in
            configured.draw(in: rect)
            colour.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
    }

    private func startServer() {
        let path = ProcessInfo.processInfo.environment["SQUAWK_SOCKET"] ?? SocketPath.defaultSocket
        let server = RequestServer(path: path) { [weak self] request, reply in
            Task { @MainActor in self?.accept(request, reply: reply) }
        } abandoned: { [weak self] id in
            Task { @MainActor in self?.drop(id) }
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

    /// The hook behind this arc is gone, so nothing is listening for a decision.
    private func drop(_ id: String) {
        guard roster.entry(id: id) != nil else { return }
        replies.removeValue(forKey: id)
        roster.remove(id: id)
        ring.selectedID = roster.entries.first?.id
        render()
        if roster.isEmpty { hide() }
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
        let attention = !roster.isEmpty
        statusItem?.button?.image = statusImage(attention: attention)
        statusItem?.button?.title = attention ? " \(roster.count)" : ""
        waitingItem.title = roster.isEmpty
            ? "Nothing waiting"
            : "\(roster.count) waiting"
        visibilityItem.title = (panel?.isVisible ?? false) ? "Hide Dial" : "Show Dial"
    }

    private func show() {
        guard let panel else { return }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        fade(to: pointerInside ? 1.0 : Settings.opacity)
    }

    private func hide() {
        guard !Settings.alwaysVisible else { return }
        hoverCard.hide()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor [weak panel] in
                // Only actually order out if nothing arrived while it was fading.
                if panel?.alphaValue == 0 { panel?.orderOut(nil) }
            }
        }
    }

    /// A dial set to fade into the background still has to be readable the moment
    /// you look at it, so pointing at it brings it back to solid.
    private func setSolid(_ inside: Bool) {
        pointerInside = inside
        guard panel?.isVisible == true else { return }
        fade(to: inside ? 1.0 : Settings.opacity)
    }

    func applyOpacity(_ value: Double) {
        Settings.opacity = value
        flushSettings()
        guard !pointerInside else { return }
        panel?.alphaValue = value
    }

    private func fade(to alpha: Double) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = alpha
        }
    }

    @objc private func toggle() {
        guard let panel else { return }
        if panel.isVisible {
            // Hiding by hand contradicts the pin, so the pin comes off with it
            // rather than the dial reappearing and the menu insisting otherwise.
            if Settings.alwaysVisible {
                Settings.alwaysVisible = false
                flushSettings()
            }
            hide()
        } else {
            show()
        }
    }
}

// MARK: - Menu actions

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        dailyItem.state = Settings.checksDaily ? .on : .off
        if !LoginItem.isAvailable {
            loginItem.state = .off
            loginItem.isEnabled = false
            loginItem.toolTip = LoginItem.statusDescription
        } else {
            loginItem.isEnabled = true
            loginItem.state = LoginItem.awaitingApproval
                ? .mixed
                : (LoginItem.isEnabled ? .on : .off)
            loginItem.toolTip = LoginItem.statusDescription
        }
        let visible = panelIsVisible
        visibilityItem.title = visible ? "Hide Dial" : "Show Dial"
        visibilityItem.image = Self.symbol(visible ? "eye.slash" : "eye")
        waitingItem.title = waitingSummary
        waitingItem.image = Self.symbol(
            roster.isEmpty ? "checkmark.circle" : "clock",
            colour: roster.isEmpty ? Palette.complete : Palette.waiting
        )
        for item in sizeItems {
            item.state = (item.representedObject as? String) == currentSizeName ? .on : .off
        }
        alwaysItem.state = Settings.alwaysVisible ? .on : .off
        opacityControl?.value = Settings.opacity
        sizeControl?.value = Double(diameter)
    }
}

extension AppDelegate {
    @objc func toggleAlwaysVisible() {
        Settings.alwaysVisible.toggle()
        if Settings.alwaysVisible {
            show()
        } else if roster.isEmpty {
            hide()
        }
        flushSettings()
    }

    @objc func toggleDailyChecks() {
        Settings.checksDaily.toggle()
        flushSettings()
        if Settings.checksDaily { runUpdateCheck(announceWhenCurrent: false) }
    }

    @objc func toggleLoginItem() {
        let wanted = !LoginItem.isEnabled
        if let message = LoginItem.set(wanted) {
            present(title: "Open at Login", message: message)
        }
    }

    /// Flushed explicitly rather than relying on the periodic write, so a
    /// setting changed a moment before quitting is not lost.
    func flushSettings() {
        panel?.saveFrame(usingName: "SquawkDial")
        UserDefaults.standard.synchronize()
    }

    @objc func checkForUpdates() {
        runUpdateCheck(announceWhenCurrent: true)
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
        if asset != nil { alert.addButton(withTitle: "Install and Relaunch") }
        alert.addButton(withTitle: "Release Notes")
        alert.addButton(withTitle: "Later")

        let choice = alert.runModal()
        guard let asset else {
            if choice == .alertFirstButtonReturn { NSWorkspace.shared.open(page) }
            return
        }
        switch choice {
        case .alertFirstButtonReturn: install(asset)
        case .alertSecondButtonReturn: NSWorkspace.shared.open(page)
        default: break
        }
    }

    /// Verified before anything is swapped, and the old copy is kept until the
    /// new one is in place, so a failed update leaves a working app behind.
    private func install(_ asset: URL) {
        let progress = NSAlert()
        progress.messageText = "Downloading Squawk"
        progress.informativeText = "Verifying the signature before it is installed."
        let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 260, height: 20))
        spinner.style = .bar
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        progress.accessoryView = spinner
        progress.addButton(withTitle: "Cancel")

        // The flag lives on the main actor: staging can finish before the modal
        // is up, and stopping a modal that never started would hang it.
        updateFinished = false
        Installer.stage(dmg: asset) { staged in
            Task { @MainActor in
                self.updateFinished = true
                NSApp.stopModal()
                switch staged {
                case .ready(let swap):
                    self.server?.stop()
                    swap()
                    NSApp.terminate(nil)
                case .failed(let message):
                    self.present(title: "Update failed", message: """
                    \(message)

                    Nothing was changed. Download it from the release page instead.
                    """)
                }
            }
        }
        if !updateFinished { progress.runModal() }
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

// MARK: - Size, homepage, uninstall

extension AppDelegate {
    @objc func pickSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        applyDiameter(DialSize.named(raw).diameter)
    }

    @objc func openProject() { NSWorkspace.shared.open(Updates.repoURL) }

    /// Destructive and outward facing, so it says exactly what it will do and
    /// takes an explicit confirmation first.
    @objc func uninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall Squawk?"
        alert.informativeText = """
        This removes the PreToolUse hook from ~/.claude/settings.json, turns off \
        Open at Login, and deletes ~/.squawk.

        Squawk is moved to the Trash, not deleted, so you can put it back. Your \
        agents keep working and fall back to the normal terminal prompt.
        """
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let report = Uninstaller.removeTraces()
        if let message = report.hookMessage {
            present(title: "Hook not removed", message: """
            \(message)

            Remove the squawk-hook entry from ~/.claude/settings.json by hand \
            before deleting the app.
            """)
            return
        }

        if let failure = Uninstaller.trashBundleAfterQuit() {
            present(title: "Squawk uninstalled", message: """
            The hook and settings are gone. \(failure)

            Drag Squawk to the Trash from your Applications folder.
            """)
        }
        server?.stop()
        NSApp.terminate(nil)
    }
}
