import AppKit
import QuartzCore
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
    let rememberedItem = NSMenuItem(title: "Remembered Answers", action: nil, keyEquivalent: "")
    /// Both glyphs are built once; rebuilding them on every render flickers.
    private var glyphCache: [Bool: NSImage] = [:]
    private var pointerInside = false
    private var updateFinished = false
    private let face = FaceView()
    private var lastFaceEvent: FaceEvent?
    private var lastFaceEventAt = Date.distantPast
    private var idleSince = Date()
    private var faceTimer: Timer?
    private var rules = RuleStore(always: RuleFile.load())
    private var opacityControl: SliderRow?
    private var sizeControl: SliderRow?
    private var sweeper: Timer?
    private var scheduleTimer: Timer?
    private let hoverCard = HoverCard()
    private var diameter = Settings.diameter
    private var cardWidthConstraint: NSLayoutConstraint?

    /// Only for a request that predates `waitSeconds` on the wire. Current hooks
    /// declare their own budget and the roster expires each arc on that.
    private let fallbackLifetime: TimeInterval = 120

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Settings.migrateFromDefaultsIfNeeded()
        buildPanel()
        buildStatusItem()
        startServer()

        sweeper = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sweep() }
        }

        // Expression follows state, so it has to be re-evaluated on a clock as
        // well as on events: a reaction expires and a quiet spell becomes sleep.
        faceTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateFace() }
        }

        // Design review: the panel is normally only raised by a waiting request,
        // so the cleared state is otherwise impossible to look at.
        if Settings.alwaysVisible || CommandLine.arguments.contains("--preview-empty") {
            show()
        }

        // Design review for the one panel Squawk draws itself, which is
        // otherwise only reachable by clicking a menu row.
        if CommandLine.arguments.contains("--preview-panel") {
            present(title: "Up to date", message: "Squawk \(Updates.bundleVersion) is the latest release.")
            NSApp.terminate(nil)
        }

        // Exercises the real update flow, panel and swap included. The earlier
        // test drove only the staging half, which is why a hang in the panel
        // half shipped twice.
        if let index = CommandLine.arguments.firstIndex(of: "--test-update"),
           index + 1 < CommandLine.arguments.count,
           let url = URL(string: CommandLine.arguments[index + 1]) {
            install(url)
        }

        checkScheduleIfDue()
        // A scheduled slot can pass while the app is simply sitting there, so
        // the schedule is polled rather than only consulted at launch.
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkScheduleIfDue() }
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
        detail.tier = DialGeometry.tier(diameter)
        ring.onSelect = { [weak self] id in self?.select(id) }
        ring.onHover = { [weak self] id in self?.hover(id) }
        ring.onMouseInside = { [weak self] inside in self?.setSolid(inside) }
        ring.onPoke = { [weak self] in self?.poke() }
        background.addSubview(ring)

        face.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(face)

        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.onAllow = { [weak self] in self?.settle(.allow) }
        detail.onDeny = { [weak self] in self?.settle(.deny) }
        detail.onOpenPane = { [weak self] in self?.openPane() }
        detail.onAllowSession = { [weak self] in self?.remember(forever: false) }
        detail.onAllowAlways = { [weak self] in self?.remember(forever: true) }
        detail.onDismiss = { [weak self] in self?.dismissSelected() }
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

            face.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            face.centerYAnchor.constraint(equalTo: background.centerYAnchor),
            face.widthAnchor.constraint(equalTo: background.widthAnchor, multiplier: 0.52),
            face.heightAnchor.constraint(equalTo: face.widthAnchor),
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
        detail.tier = DialGeometry.tier(next)
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

    /// Tinted rather than templated, so the bar carries the app's own colour:
    /// brand cyan at rest, and the waiting amber when an agent needs you, which
    /// is the same amber as the arcs.
    private func statusImage(attention: Bool) -> NSImage? {
        if let cached = glyphCache[attention] { return cached }
        guard let url = Bundle.main.url(forResource: "StatusTemplate", withExtension: "png"),
              let base = NSImage(contentsOf: url)
        else { return nil }
        base.size = NSSize(width: 18, height: 18)

        let colour = attention ? Palette.waiting : Palette.brand
        let tinted = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            colour.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        glyphCache[attention] = tinted
        return tinted
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        visibilityItem.target = self
        visibilityItem.action = #selector(toggle)
        visibilityItem.keyEquivalent = "d"
        visibilityItem.keyEquivalentModifierMask = [.command, .shift]
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

        let updates = makeItem("Check for Updates\u{2026}", #selector(checkForUpdates),
                               symbol: "arrow.triangle.2.circlepath")
        updates.keyEquivalent = "u"
        updates.keyEquivalentModifierMask = [.command]
        menu.addItem(updates)
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
        homeItem.image = GitHubMark.image(size: 13) ?? Self.symbol("globe", colour: Palette.brand)
        homeItem.toolTip = Updates.repoURL.absoluteString
        menu.addItem(homeItem)

        let settings = makeItem("Open Settings File", #selector(openConfig), symbol: "doc.text")
        settings.toolTip = Settings.configPath
        menu.addItem(settings)

        let site = makeItem("Squawk Website", #selector(openSite), symbol: "globe")
        site.toolTip = Updates.siteURL.absoluteString
        menu.addItem(site)
        menu.addItem(.separator())

        rememberedItem.image = Self.symbol("checklist")
        menu.addItem(rememberedItem)
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
        // Anything new from a session proves it is no longer sitting idle, so
        // its "waiting for you" arc has served its purpose.
        let idleKey = "notify:" + request.sessionId
        if request.id != idleKey, roster.entry(id: idleKey) != nil {
            drop(idleKey, reacting: false)
        }
        // A remembered answer settles it without the dial appearing at all.
        if request.awaitsDecision,
           rules.allows(tool: request.tool, summary: request.summary, sessionId: request.sessionId) {
            reply(DecisionReply(id: request.id, decision: .allow, reason: "Remembered by Squawk"))
            return
        }
        // Arriving while it was asleep is a start; arriving while it was awake
        // is just work.
        if roster.isEmpty, Date().timeIntervalSince(idleSince) >= FaceMood.sleepAfter {
            noteFace(.startled)
        }
        replies[request.id] = reply
        roster.add(request)
        if ring.selectedID == nil { ring.selectedID = request.id }
        render()
        show()
    }

    /// The hook behind this arc is gone, so nothing is listening for a decision.
    private func drop(_ id: String, reacting: Bool = true) {
        guard roster.entry(id: id) != nil else { return }
        if reacting { noteFace(.abandoned) }
        replies.removeValue(forKey: id)
        roster.remove(id: id)
        ring.selectedID = roster.entries.first?.id
        render()
        if roster.isEmpty { hide() }
    }

    /// Answers this call and stops asking for the same shape of call, which is
    /// how prompting decays instead of becoming something you dismiss unread.
    private func remember(forever: Bool) {
        guard let id = ring.selectedID, let entry = roster.entry(id: id) else { return }

        // Always is standing permission across every future session, written to
        // disk. One stray click once granted `rm -rf`, so it states the scope
        // and takes a confirmation. Session is bounded and does not.
        if forever {
            let scope = PermissionRule.key(
                tool: entry.request.tool, summary: entry.request.summary
            ).describedScope
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Always allow \(scope)?"
            alert.informativeText = """
            Squawk will approve this without asking, in every session from now             on, until you forget it from the menu.
            """
            alert.addButton(withTitle: "Always Allow")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        rules.remember(
            tool: entry.request.tool,
            summary: entry.request.summary,
            sessionId: entry.request.sessionId,
            forever: forever
        )
        if forever { RuleFile.save(rules.always) }
        finish(id: id, decision: .allow, reason: "Remembered by Squawk")
    }

    private func settle(_ decision: Decision) {
        guard let id = ring.selectedID else { return }
        finish(id: id, decision: decision, reason: decision == .deny ? "Denied from Squawk" : nil)
    }

    private func finish(id: String, decision: Decision, reason: String?) {
        // Clearing the last of several is relief; clearing one is just an answer.
        let wasBacklog = roster.count > 1
        noteFace(decision == .allow ? .approved : .denied)
        if let reply = replies.removeValue(forKey: id) {
            reply(DecisionReply(id: id, decision: decision, reason: reason))
        }
        roster.remove(id: id)
        // Clearing the last of several is relief, and it replaces the plain
        // acknowledgement rather than queueing behind it.
        if wasBacklog, roster.isEmpty { noteFace(.relieved) }
        ring.selectedID = roster.entries.first?.id
        render()
        if roster.isEmpty { hide() }
    }

    /// Clears an entry nothing is waiting on. Only attention entries can be
    /// dismissed; a decision has a blocked hook and must be answered.
    private func dismissSelected() {
        guard let id = ring.selectedID, let entry = roster.entry(id: id),
              !entry.request.awaitsDecision
        else { return }
        drop(id, reacting: false)
    }

    private func openPane() {
        guard let id = ring.selectedID, let entry = roster.entry(id: id) else { return }
        // Silence was the bug here: a pane that could not be found looked
        // identical to one that was focused behind the dial.
        switch PaneOpener.focus(entry.request) {
        case .focusedPane:
            // Going to the pane is dealing with it, so it stops asking.
            if !entry.request.awaitsDecision { drop(id, reacting: false) }
        case .activatedApp(let name):
            NSLog("squawk: brought %@ forward; no scripted pane lookup", name)
        case .noTerminal:
            present(title: "No terminal found", message: """
            Squawk could not work out which terminal this session belongs to, so             there is nothing to bring forward.
            """)
        case .failed(let message):
            present(title: "Could not open the pane", message: message)
        }
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
        // Leaving an arc falls back to the selected one while the pointer is
        // still on the dial, rather than the card blinking out mid-read.
        let wanted = id ?? (pointerInside ? ring.selectedID : nil)
        guard let wanted, let entry = roster.entry(id: wanted), let panel else {
            hoverCard.hide()
            return
        }
        hoverCard.show(entry.request, besides: panel)
    }

    private func select(_ id: String) {
        ring.selectedID = id
        render()
    }

    private var pokeCount = 0
    private var lastPokeAt = Date.distantPast
    private var lastPokeFace: FaceExpression?

    /// Prodding it plays along, and keeping it up stops being funny. The face is
    /// chosen here rather than at render time, so a random pick holds for the
    /// whole reaction instead of changing every frame.
    private func poke() {
        let now = Date()
        pokeCount = now.timeIntervalSince(lastPokeAt) > Poke.bout ? 1 : pokeCount + 1
        lastPokeAt = now
        let face = Poke.reaction(to: pokeCount, avoiding: lastPokeFace)
        lastPokeFace = face
        noteFace(.poked(face))
    }

    private func noteFace(_ event: FaceEvent) {
        lastFaceEvent = event
        lastFaceEventAt = Date()
        updateFace()
    }

    /// The face is a function of state, not something each call site sets.
    private func updateFace() {
        let awaiting = roster.entries.contains { $0.request.awaitsDecision }
        // Risk is judged on what you are actually being shown, not on the worst
        // thing in the queue, so the face matches the command under your eyes.
        let selected = ring.selectedID.flatMap { roster.entry(id: $0) }?.request
        let risky = selected.map {
            $0.awaitsDecision && RiskSignal.isRisky(tool: $0.tool, summary: $0.summary)
        } ?? false
        let expression = FaceMood.expression(
            waiting: roster.count,
            awaitingDecision: awaiting,
            lastEvent: lastFaceEvent,
            eventAge: Date().timeIntervalSince(lastFaceEventAt),
            idleFor: Date().timeIntervalSince(idleSince),
            risky: risky
        )
        face.expression = expression

        // The card and the face share the middle, so only one is up at a time,
        // and anything waiting on you outranks the face. Answering the last
        // request empties the roster, so a reaction is still seen; it just never
        // hides a request that is still there.
        let showFace = roster.isEmpty
        face.isHidden = !showFace
        detail.isHidden = showFace || ring.selectedID == nil

        if showFace, panel?.isVisible == false, Settings.alwaysVisible { show() }
    }

    private func render() {
        ring.roster = roster
        let selected = ring.selectedID.flatMap { roster.entry(id: $0) }
        // Nothing waiting means nothing to act on, so the card collapses and the
        // dial is left alone in the middle rather than sat above three dead buttons.
        detail.show(selected, waiting: roster.count)
        if roster.isEmpty { idleSince = min(idleSince, Date()) } else { idleSince = Date() }
        updateFace()
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
        fade(to: pointerInside ? 1.0 : Settings.opacity,
             duration: 0.26, curve: .easeOut)
    }

    private func hide() {
        guard !Settings.alwaysVisible else { return }
        hoverCard.hide()
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
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

        // The card truncates, and at small dial sizes it does not show the
        // command at all, so pointing anywhere at the dial reveals it.
        if inside {
            if let id = ring.selectedID { hover(id) }
        } else {
            hoverCard.hide()
        }
    }

    func applyOpacity(_ value: Double) {
        Settings.opacity = value
        flushSettings()
        guard !pointerInside else { return }
        panel?.alphaValue = value
    }

    /// Eased rather than linear, and long enough to read as a transition. A
    /// dial that blinks in and out is the thing that makes a floating window
    /// feel like an interruption.
    private func fade(
        to alpha: Double,
        duration: TimeInterval = 0.18,
        curve: CAMediaTimingFunctionName = .easeInEaseOut
    ) {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: curve)
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
        dailyItem.state = Settings.checksForUpdates ? .on : .off
        dailyItem.title = "Check at " + Settings.checkTimes.map(\.text).joined(separator: " and ")
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
        rebuildRemembered()
        opacityControl?.value = Settings.opacity
        sizeControl?.value = Double(diameter)
    }
}

extension AppDelegate {
    /// Standing permissions have to be visible and revocable, or they are just
    /// a hole you cannot see.
    func rebuildRemembered() {
        let rules = self.rules.always.sorted { ($0.tool, $0.prefix) < ($1.tool, $1.prefix) }
        rememberedItem.title = rules.isEmpty
            ? "No Remembered Answers"
            : "Remembered Answers (\(rules.count))"
        guard !rules.isEmpty else {
            rememberedItem.submenu = nil
            rememberedItem.isEnabled = false
            return
        }
        rememberedItem.isEnabled = true
        let submenu = NSMenu()
        for rule in rules {
            let item = NSMenuItem(title: rule.describedScope,
                                  action: #selector(forgetRule(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = rule
            item.toolTip = "Forget this, and ask again next time"
            submenu.addItem(item)
        }
        submenu.addItem(.separator())
        let forget = NSMenuItem(title: "Forget All", action: #selector(forgetAllRules),
                                keyEquivalent: "")
        forget.target = self
        submenu.addItem(forget)
        rememberedItem.submenu = submenu
    }

    @objc func forgetRule(_ sender: NSMenuItem) {
        guard let rule = sender.representedObject as? PermissionRule else { return }
        var always = rules.always
        always.remove(rule)
        rules = RuleStore(always: always)
        RuleFile.save(always)
        rebuildRemembered()
    }

    @objc func forgetAllRules() {
        rules = RuleStore()
        RuleFile.save([])
        rebuildRemembered()
    }

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
        Settings.checksForUpdates.toggle()
        if Settings.checksForUpdates { runUpdateCheck(announceWhenCurrent: false) }
    }

    /// Runs when a scheduled time has passed that the last check predates, so a
    /// machine asleep at ten checks on waking rather than skipping the slot.
    private func checkScheduleIfDue() {
        guard Settings.checksForUpdates else { return }
        guard UpdateSchedule.isDue(at: Settings.checkTimes, lastCheck: UpdateSchedule.lastCheck())
        else { return }
        runUpdateCheck(announceWhenCurrent: false)
    }

    @objc func toggleLoginItem() {
        let wanted = !LoginItem.isEnabled
        Settings.opensAtLogin = wanted
        if let message = LoginItem.set(wanted) {
            present(title: "Open at Login", message: message)
        }
    }

    /// Flushed explicitly rather than relying on the periodic write, so a
    /// setting changed a moment before quitting is not lost.
    /// The config file is written on every change, so this only has to persist
    /// the window frame, which AppKit still owns.
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
        let cancellation = Installer.Cancellation()
        let panel = ProgressPanel(
            title: "Updating Squawk",
            message: """
            Downloading, then checking the signature before anything is replaced. \
            Cancel leaves the installed version untouched.
            """
        )
        updateFinished = false
        panel.show { [weak self] in
            self?.updateFinished = true
            cancellation.cancel()
        }

        Installer.stage(dmg: asset, cancellation: cancellation) { staged in
            // DispatchQueue rather than a main-actor Task: this has to arrive
            // even while a run loop is busy, and a Task hop did not.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.updateFinished else { return }
                    self.updateFinished = true
                    panel.close()
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
        }
    }

    func present(title: String, message: String) {
        InfoPanel.show(title: title, message: message)
    }
}

// MARK: - Size, homepage, uninstall

extension AppDelegate {
    @objc func pickSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        applyDiameter(DialSize.named(raw).diameter)
    }

    @objc func openProject() { NSWorkspace.shared.open(Updates.repoURL) }
    @objc func openSite() { NSWorkspace.shared.open(Updates.siteURL) }

    /// Reveals rather than opens: the file is small and hand editable, and
    /// Finder is a safer default than whatever owns .json.
    @objc func openConfig() {
        let path = Settings.configPath
        if !FileManager.default.fileExists(atPath: path) { Settings.reload() }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Destructive and outward facing, so it says exactly what it will do and
    /// takes an explicit confirmation first.
    @objc func uninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Uninstall Squawk?"
        // Naming every copy matters: removing only the running one looks exactly
        // like uninstall having failed.
        let copies = Uninstaller.installedCopies()
        let list = copies.map { "  " + $0.path }.joined(separator: "\n")
        alert.informativeText = """
        This removes the PreToolUse hook from your agent settings, turns off \
        Open at Login, and deletes ~/.squawk.

        These copies go to the Trash, not deleted, so you can put them back:
        \(list)

        Your agents keep working and fall back to the normal terminal prompt.
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

        if let failure = Uninstaller.trashBundlesAfterQuit(copies) {
            present(title: "Squawk uninstalled", message: """
            The hook and settings are gone. \(failure)

            Drag Squawk to the Trash from your Applications folder.
            """)
        }
        server?.stop()
        NSApp.terminate(nil)
    }
}
