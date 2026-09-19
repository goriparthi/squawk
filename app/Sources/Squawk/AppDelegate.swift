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
    var petItems: [NSMenuItem] = []
    var breakItems: [NSMenuItem] = []
    let rememberedItem = NSMenuItem(title: "Remembered Answers", action: nil, keyEquivalent: "")
    /// Both glyphs are built once; rebuilding them on every render flickers.
    private var glyphCache: [String: NSImage] = [:]
    private var pointerInside = false
    private var restlessUntil: Date?
    private var updateFinished = false
    private var background: CircleBackgroundView? { panel?.contentView as? CircleBackgroundView }
    private let face = FaceView()
    /// The modelled companion, which is what the full style is now. The flat
    /// drawing stays for the face style, where there is no body to model.
    private lazy var companion = CompanionView(face: face.animator,
                                               persona: Settings.persona)
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
    private var bubbleCentreConstraint: NSLayoutConstraint?
    private var cardInBubbleOffset: NSLayoutConstraint?
    private var bubbleAboveConstraints: [NSLayoutConstraint] = []
    private var bubbleBelowConstraints: [NSLayoutConstraint] = []
    /// Whether the bubble is under the pet rather than over it.
    private var bubbleIsBelow = false
    private var castItems: [NSMenuItem] = []
    private let listener = SystemAudio()
    private let privacy = PrivacyWatch()
    let nowPlayingItem = NSMenuItem(title: "React to Audio", action: nil, keyEquivalent: "")
    let wellnessItem = NSMenuItem(title: "Look After Me", action: nil, keyEquivalent: "")
    let speakItem = NSMenuItem(title: "Speak Aloud", action: nil, keyEquivalent: "")
    /// Rebuilt every time it opens, because a voice can finish downloading
    /// while the menu is shut.
    private let voiceMenu = NSMenu()
    private lazy var speaker = Speaker(choice: .restored(Settings.voiceId))
    private var voicePanel: ProgressPanel?
    private var voiceFetch: VoicePack.Fetch?
    private var speechEndsAfter = Date.distantPast
    let phraseItem = NSMenuItem(title: "Phrase with Ollama", action: nil, keyEquivalent: "")
    let wakeItem = NSMenuItem(title: "Listen for its Name", action: nil, keyEquivalent: "")
    let pushItem = NSMenuItem(title: "Push to Talk", action: nil, keyEquivalent: "")
    private let ears = Ears()
    private let hotkey = Hotkey()
    /// A risky approval that has been asked about and is waiting for a yes.
    private var pendingVoice: VoiceCommand.Pending?
    /// True while the hotkey is held, so a wake word is not also needed.
    private var holdingToTalk = false
    /// When it last heard its own name, which the ears show for a moment.
    private var heardNameAt = Date.distantPast
    /// The key has been let go but the sentence it holds has not arrived yet.
    /// Without this the final transcript of a held key is read as though it
    /// were overheard, and asked for a wake word it was never going to have.
    private var awaitingHeldSentence = false
    /// Models on this machine, looked up rather than assumed. Refreshed when
    /// the menu opens, because Ollama starts and stops independently of us.
    private var localModels: [String] = []
    private var phrasingModel: String? {
        Ollama.choose(from: localModels, configured: Settings.phrasingModel)
    }
    /// When this run of work started, and what has been said about it.
    private var wellnessState = Wellness.State(startedAt: Date())
    /// The last request from an agent, which counts as being at the desk.
    private var lastAgentTrafficAt = Date()
    private let launchedAt = Date()
    private var wellnessTimer: Timer?
    private var lastPrivacy = PrivacyState.clear
    /// The one slot everything it says goes through; `Speaking` holds the rule.
    private var speaking = Speaking()
    private var speechTimer: Timer?
    private var lastFortune: String?
    private var headWidthConstraint: NSLayoutConstraint?
    private var headTopConstraint: NSLayoutConstraint?
    private let bubble = BubbleView()
    private var insideConstraints: [NSLayoutConstraint] = []
    private var bubbleConstraints: [NSLayoutConstraint] = []

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
            Task { @MainActor in
                self?.updateFace()
                self?.updateListening()
                self?.nudgeIfDue()
            }
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
        listener.stop()
        privacy.stop()
        wellnessTimer?.invalidate()
    }

    private func buildPanel() {
        // Square window, circular paint. The content has to live inside the
        // inner circle, so its width is that circle's inscribed square.
        let canvas = Self.canvasSize(head: diameter, style: Settings.petStyle)
        let panel = SquawkPanel(contentRect: NSRect(origin: .zero, size: canvas))
        let background = CircleBackgroundView(frame: NSRect(origin: .zero, size: canvas))
        background.autoresizingMask = [.width, .height]

        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.diameter = diameter
        detail.tier = DialGeometry.tier(diameter, for: Settings.petStyle)
        ring.onSelect = { [weak self] id in self?.select(id) }
        ring.onHover = { [weak self] id in self?.hover(id) }
        ring.onMouseInside = { [weak self] inside in
            self?.setSolid(inside)
            if inside { self?.wakeFromIdle() }
        }
        ring.onPoke = { [weak self] in self?.poke() }
        background.addSubview(ring)

        face.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(face)

        companion.translatesAutoresizingMaskIntoConstraints = false
        companion.onTummyRub = { [weak self] in self?.tummyRubbed() }
        companion.onGiggle = { [weak self] in self?.tickled() }
        companion.speechLevel = { [weak self] in self?.speaker.level ?? 0 }
        companion.onTummyDoubleClick = { [weak self] in self?.startDancing() }
        companion.onPoke = { [weak self] in self?.poke() }
        background.addSubview(companion)

        bubble.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(bubble)

        detail.translatesAutoresizingMaskIntoConstraints = false
        detail.onAllow = { [weak self] in self?.settle(.allow) }
        detail.onDeny = { [weak self] in self?.settle(.deny) }
        detail.onOpenPane = { [weak self] in self?.openPane() }
        detail.onAllowSession = { [weak self] in self?.remember(forever: false) }
        detail.onAllowAlways = { [weak self] in self?.remember(forever: true) }
        detail.onDismiss = { [weak self] in self?.dismissSelected() }
        background.addSubview(detail)

        // Nudged sideways when the pet is parked against a screen edge, so the
        // card is never half off the display.
        let bubbleCentre = bubble.centerXAnchor.constraint(
            equalTo: background.centerXAnchor)
        bubbleCentreConstraint = bubbleCentre

        let cardWidth = detail.widthAnchor.constraint(
            equalToConstant: DialGeometry.cardWidth(diameter, for: Settings.petStyle))
        cardWidthConstraint = cardWidth

        // The ring tracks the head, which is the whole canvas in face style and
        // the top of it in full style.
        let ringWidth = ring.widthAnchor.constraint(equalToConstant: diameter)
        // Set at creation, not only in resizeToFit: the first layout happens
        // before any resize, and a zero here put the face above the head.
        let ringTop = ring.topAnchor.constraint(
            equalTo: background.topAnchor,
            constant: Settings.petStyle == .full
                ? BodyGeometry.bubbleHeight(head: diameter)
                : (canvas.height - diameter) / 2
        )
        headWidthConstraint = ringWidth
        headTopConstraint = ringTop

        NSLayoutConstraint.activate([
            ring.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            ringTop,
            ringWidth,
            ring.heightAnchor.constraint(equalTo: ring.widthAnchor),

            cardWidth,

            bubbleCentre,

            // The bubble is the card plus its padding, so a one line notice
            // gets a small bubble rather than the room the longest one needs.
            bubble.widthAnchor.constraint(equalTo: detail.widthAnchor,
                                          constant: 2 * DialGeometry.bubblePadding),
            bubble.heightAnchor.constraint(equalTo: detail.heightAnchor,
                                           constant: 2 * DialGeometry.bubblePadding
                                               + bubble.tailHeight),

            // The model gets everything below the bubble, which is the room the
            // drawn body had. Given the whole window it would be framed for a
            // very tall viewport and its arms would fall outside the view.
            companion.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            companion.trailingAnchor.constraint(equalTo: background.trailingAnchor),


            face.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            face.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
            face.widthAnchor.constraint(equalTo: ring.widthAnchor, multiplier: 0.52),
            face.heightAnchor.constraint(equalTo: face.widthAnchor),
        ])

        // Two homes for the bubble: above the pet, which is the normal one, and
        // below it, for a pet parked against the top of the screen where a
        // bubble above would be off the display. The pet does not move between
        // them; the window does, by the bubble's height, so the pet stays put.
        bubbleAboveConstraints = [
            bubble.bottomAnchor.constraint(equalTo: ring.topAnchor),
            companion.topAnchor.constraint(equalTo: ring.topAnchor),
            companion.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ]
        bubbleBelowConstraints = [
            companion.topAnchor.constraint(equalTo: background.topAnchor),
            companion.bottomAnchor.constraint(equalTo: bubble.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ]
        NSLayoutConstraint.activate(bubbleAboveConstraints)

        // Two homes for the card: inside the head, or speaking above it.
        insideConstraints = [
            detail.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            detail.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
        ]
        // The card sits clear of the tail, which is at the bottom of the bubble
        // when it is above the pet and at the top when it is below.
        cardInBubbleOffset = detail.centerYAnchor.constraint(
            equalTo: bubble.centerYAnchor, constant: bubble.tailHeight / 2)
        bubbleConstraints = [
            detail.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
            cardInBubbleOffset!,
        ]
        applyCardPlacement(Settings.petStyle)
        bubble.tailOffset = -diameter * 0.26

        panel.contentView = background
        // A dock belongs where you put it, so the frame is remembered. The
        // default sits clear of the menu bar and the Dock rather than centred
        // over whatever you are reading.
        // Restores where it was left. The saved frame also carries the size it
        // had then, so the stored preference is reapplied about the same centre
        // rather than letting a stale frame decide how big the dial is.
        // The saved frame was saved with the bubble on one side; start there.
        if Settings.bubbleBelow { layoutBubble(below: true) }
        let restored = panel.setFrameUsingName("SquawkDial")
        panel.setFrameAutosaveName("SquawkDial")
        if restored {
            // The saved frame carries the size it had then, which may be another
            // style's canvas entirely. Reapply the current one about the centre.
            let centre = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
            panel.setContentSize(canvas)
            panel.setFrameOrigin(NSPoint(
                x: (centre.x - canvas.width / 2).rounded(),
                y: (centre.y - canvas.height / 2).rounded()
            ))
            panel.setFrame(Self.nudgedOnScreen(panel.frame), display: false)
        } else if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - canvas.width - 24,
                y: visible.minY + 24
            ))
        }
        panel.saveFrame(usingName: "SquawkDial")
        panel.alphaValue = Settings.opacity
        self.panel = panel
        // Dragged to an edge, the bubble has to slide back inside the display
        // exactly as it does when the pet is resized there.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepBubbleOnScreen() }
        }
        // After the panel owns the view, not before: `background` reads through
        // `panel`, so calling this earlier set the flag on nothing and the flat
        // dial was drawn behind the model until the first resize.
        applyRenderer(Settings.petStyle)
        listener.onSpectrum = { [weak self] spectrum in
            guard let self else { return }
            companion.hear(isTalking ? nil : spectrum)
        }
        startListeningIfWanted()
        // Only if it was already granted: launch is not the moment to ask.
        if Settings.listensForWakeWord || Settings.pushToTalk, Ears.isPermitted {
            applyListening(wake: Settings.listensForWakeWord, push: Settings.pushToTalk)
        }
        // Always on. It opens nothing and needs no permission; it is the same
        // question the system's own dots answer, and a pet that shows it is
        // more use than one that does not.
        privacy.onChange = { [weak self] state in
            self?.applyPrivacy(state)
            self?.updateStatusItem(privacy: state)
        }
        privacy.start()
        startWellnessClock()
        render()
        panel.invalidateShadow()
    }

    /// What the window needs for a given head, which is more than the head
    /// itself once there are arms to swing.
    static func canvasSize(head: CGFloat, style: PetStyle) -> NSSize {
        switch style {
        case .face: NSSize(width: head, height: head)
        case .full:
            NSSize(width: BodyGeometry.canvas(head: head).width,
                   height: BodyGeometry.canvas(head: head).height)
        }
    }

    /// Swaps the modelled companion for one in another character's colours.
    private func rebuildCompanion() {
        guard let background, let panel else { return }
        let replacement = CompanionView(face: face.animator, persona: Settings.persona)
        replacement.translatesAutoresizingMaskIntoConstraints = false
        replacement.onTummyRub = { [weak self] in self?.tummyRubbed() }
        replacement.onGiggle = { [weak self] in self?.tickled() }
        replacement.speechLevel = { [weak self] in self?.speaker.level ?? 0 }
        replacement.onTummyDoubleClick = { [weak self] in self?.startDancing() }
        replacement.onPoke = { [weak self] in self?.poke() }
        replacement.pose = companion.pose
        companion.removeFromSuperview()
        companion = replacement
        background.addSubview(replacement, positioned: .below, relativeTo: bubble)
        NSLayoutConstraint.activate([
            replacement.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            replacement.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            replacement.topAnchor.constraint(equalTo: ring.topAnchor),
            replacement.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        applyRenderer(Settings.petStyle)
        panel.invalidateShadow()
    }

    /// A body is modelled; a face on its own is drawn. Only one of the two is
    /// ever on screen, and the ring belongs to the drawn one.
    private func applyRenderer(_ style: PetStyle) {
        let modelled = style == .full
        companion.isHidden = !modelled
        ring.isHidden = modelled
        background?.isModelled = modelled
        if modelled { companion.stand() }
    }

    /// Keeps the whole bubble on screen when the pet is parked near an edge.
    /// The bubble slides sideways and the tail slides the other way, so it
    /// still points at the head: moving the pet instead would mean the window
    /// walking away from where it was put.
    private func keepBubbleOnScreen() {
        guard let panel, let screen = NSScreen.screens.first(where: {
            $0.frame.intersects(panel.frame)
        }) ?? NSScreen.main else { return }

        let shift = BubbleAnchor.shift(centre: panel.frame.midX,
                                       width: DialGeometry.bubbleWidth(),
                                       visible: screen.visibleFrame)
        placeBubble(above: !BubbleAnchor.shouldSitBelow(
            panelTop: panel.frame.maxY, bubbleHeight: bubbleHeightNow,
            visibleTop: screen.visibleFrame.maxY, currentlyBelow: bubbleIsBelow))
        bubbleCentreConstraint?.constant = shift
        bubble.tailOffset = -diameter * 0.26 - shift
    }

    private var bubbleHeightNow: CGFloat { BodyGeometry.bubbleHeight(head: diameter) }

    /// Moves the bubble over or under the pet. The pet stays exactly where it
    /// is on screen: the window slides by the bubble's height to make that so.
    private func placeBubble(above: Bool) {
        guard let panel, Settings.petStyle == .full, bubbleIsBelow == above else { return }
        layoutBubble(below: !above)
        var frame = panel.frame
        frame.origin.y += above ? bubbleHeightNow : -bubbleHeightNow
        panel.setFrame(frame, display: true)
    }

    /// One home or the other, without moving the window. Remembered with the
    /// frame, because the frame alone restores into whichever layout is built.
    private func layoutBubble(below: Bool) {
        bubbleIsBelow = below
        if Settings.bubbleBelow != below { Settings.bubbleBelow = below }
        NSLayoutConstraint.deactivate(below ? bubbleAboveConstraints : bubbleBelowConstraints)
        NSLayoutConstraint.activate(below ? bubbleBelowConstraints : bubbleAboveConstraints)
        headTopConstraint?.constant = below ? 0 : bubbleHeightNow
        bubble.pointsUp = below
        cardInBubbleOffset?.constant = (below ? -1 : 1) * bubble.tailHeight / 2
    }

    /// As wide as what it is showing when it speaks from the bubble, and as wide
    /// as the ring allows when it sits inside the head.
    private func applyCardWidth() {
        let style = Settings.petStyle
        cardWidthConstraint?.constant = style == .full
            ? detail.fitWidth(within: DialGeometry.bubbleCardWidth)
            : DialGeometry.cardWidth(diameter, for: style)
    }

    /// The card lives inside the head when there is no body, and in the bubble
    /// when there is, because covering the eyes defeats the point of the body.
    private func applyCardPlacement(_ style: PetStyle) {
        let speaking = style == .full
        NSLayoutConstraint.deactivate(speaking ? insideConstraints : bubbleConstraints)
        NSLayoutConstraint.activate(speaking ? bubbleConstraints : insideConstraints)
        bubble.isHidden = !speaking
    }

    func applyPetStyle(_ style: PetStyle) {
        guard style != Settings.petStyle || panel == nil else { return }
        Settings.petStyle = style
        // The face style needs a bigger head, because the card goes back inside
        // the ring. Raise a size that would no longer fit rather than clipping.
        let corrected = DialGeometry.clamp(diameter, for: style)
        if corrected != diameter {
            diameter = corrected
            Settings.diameter = corrected
            sizeControl?.value = Double(corrected)
        }
        resizeToFit()
    }

    /// Grows or shrinks in place, keeping the dial's centre where the user put
    /// it rather than pinning a corner and appearing to drift.
    func applyDiameter(_ requested: CGFloat) {
        let next = DialGeometry.clamp(requested, for: Settings.petStyle)
        guard next != diameter, panel != nil else { return }
        diameter = next
        Settings.diameter = next
        flushSettings()
        resizeToFit()
        sizeControl?.value = Double(next)
    }

    /// Applies the current head size and style to the window and its layout,
    /// keeping the whole companion centred on where it already was.
    private func resizeToFit() {
        guard let panel, let background = panel.contentView as? CircleBackgroundView else { return }
        let style = Settings.petStyle
        let canvas = Self.canvasSize(head: diameter, style: style)
        let centre = NSPoint(x: panel.frame.midX, y: panel.frame.midY)

        applyRenderer(style)
        applyCardPlacement(style)
        ring.diameter = diameter
        detail.tier = DialGeometry.tier(diameter, for: style)
        applyCardWidth()
        headWidthConstraint?.constant = diameter
        headTopConstraint?.constant = style == .full
            ? (bubbleIsBelow ? 0 : BodyGeometry.bubbleHeight(head: diameter))
            : (canvas.height - diameter) / 2

        panel.setContentSize(canvas)
        panel.setFrameOrigin(NSPoint(
            x: (centre.x - canvas.width / 2).rounded(),
            y: (centre.y - canvas.height / 2).rounded()
        ))
        panel.setFrame(Self.nudgedOnScreen(panel.frame), display: true)
        keepBubbleOnScreen()
        panel.saveFrame(usingName: "SquawkDial")
        background.needsDisplay = true
        panel.invalidateShadow()
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

    /// Wearing the same colour the pet does, so the bar and the companion are
    /// obviously the same thing, and the waiting amber the moment an agent
    /// needs you. The supplied asset asks not to be coloured, which is the
    /// right default for an icon that belongs to the system; this one belongs
    /// to a character you picked.
    private func statusImage(attention: Bool) -> NSImage? {
        let key = "\(attention)-\(Settings.persona.id)"
        if let cached = glyphCache[key] { return cached }
        guard let url = Bundle.main.url(forResource: "StatusTemplate", withExtension: "png"),
              let base = NSImage(contentsOf: url)
        else { return nil }
        base.size = NSSize(width: 18, height: 18)

        let colour = attention
            ? Palette.waiting
            : CompanionScene.colour(Settings.persona.eye)
        let tinted = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            colour.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        glyphCache[key] = tinted
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
        sizeParent.toolTip = "The face style needs at least 150 pt for the card"
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

        // The widest range any style allows; a face re-clamps itself when the
        // slider lands somewhere it cannot fit.
        let bounds = DialGeometry.range(for: .full)
        let sizeLimits = Double(bounds.lowerBound)...Double(bounds.upperBound)
        let size = SliderRow(
            title: "Pet Size",
            value: Double(diameter),
            range: sizeLimits.lowerBound...sizeLimits.upperBound,
            format: { "\(Int($0.rounded())) pt" }
        )
        size.onChange = { [weak self] value in self?.applyDiameter(CGFloat(value)) }
        let sizeItem = NSMenuItem()
        sizeItem.view = size
        menu.addItem(sizeItem)
        menu.addItem(sizeParent)

        let petParent = NSMenuItem(title: "Pet", action: nil, keyEquivalent: "")
        petParent.image = Self.symbol("figure.wave")
        let pets = NSMenu()
        for style in PetStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(pickPetStyle(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            pets.addItem(item)
            petItems.append(item)
        }
        petParent.submenu = pets
        menu.addItem(petParent)

        // The cast. One model in six colourways, so picking one is a rebuild of
        // the scene rather than a different pet to maintain.
        let castParent = NSMenuItem(title: "Character", action: nil, keyEquivalent: "")
        castParent.image = NSImage(systemSymbolName: "person.2", accessibilityDescription: nil)
        let cast = NSMenu()
        castItems.removeAll()
        for persona in Cast.all {
            let item = NSMenuItem(title: persona.name, action: #selector(pickPersona(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = persona.id
            item.toolTip = persona.tagline
            item.state = persona.id == Settings.persona.id ? .on : .off
            cast.addItem(item)
            castItems.append(item)
        }
        castParent.submenu = cast
        menu.addItem(castParent)

        nowPlayingItem.action = #selector(toggleNowPlaying)
        nowPlayingItem.target = self
        nowPlayingItem.image = NSImage(systemSymbolName: "headphones",
                                       accessibilityDescription: nil)
        nowPlayingItem.toolTip = "Wear headphones and show what is playing"
        nowPlayingItem.state = Settings.reactsToAudio ? .on : .off
        menu.addItem(nowPlayingItem)

        speakItem.action = #selector(toggleSpeaksAloud)
        speakItem.target = self
        speakItem.image = Self.symbol("waveform")
        speakItem.toolTip = "Say out loud what your agents are asking for"
        speakItem.state = Settings.speaksAloud ? .on : .off
        menu.addItem(speakItem)

        let sayItem = NSMenuItem(title: "Say What's Waiting", action: #selector(sayWhatsWaiting),
                                 keyEquivalent: "")
        sayItem.target = self
        sayItem.image = Self.symbol("bubble.left.and.text.bubble.right")
        menu.addItem(sayItem)

        wakeItem.action = #selector(toggleWakeWord)
        wakeItem.target = self
        wakeItem.image = Self.symbol("ear")
        menu.addItem(wakeItem)

        pushItem.action = #selector(togglePushToTalk)
        pushItem.target = self
        pushItem.image = Self.symbol("mic")
        pushItem.toolTip = "Hold \(Hotkey.describedDefault) anywhere and say what you want"
        pushItem.state = Settings.pushToTalk ? .on : .off
        menu.addItem(pushItem)

        phraseItem.action = #selector(togglePhrasing)
        phraseItem.target = self
        phraseItem.image = Self.symbol("text.bubble")
        phraseItem.state = Settings.phrasesWithModel ? .on : .off
        menu.addItem(phraseItem)

        let voiceParent = NSMenuItem(title: "Voice", action: nil, keyEquivalent: "")
        voiceParent.image = Self.symbol("person.wave.2")
        voiceMenu.delegate = self
        voiceParent.submenu = voiceMenu
        menu.addItem(voiceParent)

        wellnessItem.action = #selector(toggleWellness)
        wellnessItem.target = self
        wellnessItem.image = NSImage(systemSymbolName: "figure.cooldown",
                                     accessibilityDescription: nil)
        wellnessItem.toolTip = "Eye breaks, posture, water, and a word when it gets late"
        wellnessItem.state = Settings.wellness ? .on : .off
        menu.addItem(wellnessItem)

        let breakParent = NSMenuItem(title: "Break Reminder", action: nil, keyEquivalent: "")
        breakParent.image = Self.symbol("figure.walk")
        let breaks = NSMenu()
        for minutes in [0, 30, 50, 90] {
            let item = NSMenuItem(title: minutes == 0 ? "Off" : "After \(minutes) min",
                                  action: #selector(pickBreakReminder(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = minutes
            item.toolTip = minutes == 0
                ? "Never interrupt"
                : "Get restless after \(minutes) minutes with nothing answered"
            breaks.addItem(item)
            breakItems.append(item)
        }
        breakParent.submenu = breaks
        menu.addItem(breakParent)
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
        menu.addItem(makeItem("What Squawk Can Do\u{2026}", #selector(showHelp),
                              symbol: "questionmark.circle"))
        menu.addItem(homeItem)

        let settings = makeItem("Open Settings File", #selector(openConfig), symbol: "doc.text")
        settings.toolTip = Settings.configPath
        menu.addItem(settings)

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
        lastAgentTrafficAt = Date()
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
        if Settings.speaksAloud {
            speaker.say(Utterance.arrival(Briefing.item(for: request)))
        }
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
            // Going there is dealing with it, however we got there.
            if !entry.request.awaitsDecision { drop(id, reacting: false) }
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
    /// The last time you actually dealt with something, which is what the break
    /// reminder measures. Looking at it does not count as answering it.
    private var lastInteractionAt: Date?
    private var lastNudgeAt: Date?

    /// Prodding it plays along, and keeping it up stops being funny. The face is
    /// chosen here rather than at render time, so a random pick holds for the
    /// whole reaction instead of changing every frame.
    /// A rubbed tummy is answered, not logged. Nothing is waiting when it
    /// speaks, so a fortune never sits on top of a request you have to answer.
    private func tummyRubbed() {
        lastInteractionAt = Date()
        restlessUntil = nil
        noteFace(.poked(.happy))
        guard roster.isEmpty, Settings.petStyle == .full else { return }

        // Rubbed while music is playing, it tells you what it can hear rather
        // than a fortune. Asking what is playing is more use than a proverb
        // when you are clearly already listening to something.
        if companion.isHearingMusic {
            let track = NowPlaying.current()
            let app = NowPlaying.playingApplication()
            let appName = track?.source ?? app?.localizedName
            // A track from a player that will give one; a tab title from a
            // browser, which for a music site is the track; the application
            // that is making the sound; and only then a shrug.
            let tab = track == nil ? app.flatMap(NowPlaying.browserTab(for:)) : nil
            var lines: [String] = []
            if let bpm = companion.heardTempo { lines.append("\(bpm) bpm") }
            if let appName { lines.append(tab != nil ? "front tab in \(appName)" : appName) }
            guard say(Speech(kind: .nowPlaying, face: .happy,
                             until: Date().addingTimeInterval(Self.fortuneLifetime)))
            else { return }
            detail.showNowPlaying(title: track?.title ?? tab ?? appName,
                                  artist: track?.artist,
                                  detail: lines.joined(separator: "  ·  "),
                                  artwork: track?.artwork)
            applyCardWidth()
            keepBubbleOnScreen()
            show()
            updateFace()
            return
        }

        guard say(Speech(kind: .fortune, face: .happy,
                         until: Date().addingTimeInterval(Self.fortuneLifetime)))
        else { return }
        let text = Fortune.next(after: lastFortune)
        lastFortune = text
        detail.speak(text)
        applyCardWidth()
        show()
        updateFace()
    }

    /// Tapped its tummy once: a wink and a wiggle, never a poke, so tickling
    /// it never makes it cross.
    private func tickled() {
        lastInteractionAt = Date()
        restlessUntil = nil
        noteFace(.poked(.wink))
    }

    /// Double tapped its tummy, which starts the routine, and again to stop it.
    private func startDancing() {
        lastInteractionAt = Date()
        restlessUntil = nil
        speaking.stop()
        noteFace(.poked(.happy))
        companion.toggleDance()
        render()
    }

    private func poke() {
        let now = Date()
        pokeCount = now.timeIntervalSince(lastPokeAt) > Poke.bout ? 1 : pokeCount + 1
        lastPokeAt = now
        let face = Poke.reaction(to: pokeCount, avoiding: lastPokeFace)
        lastPokeFace = face
        noteFace(.poked(face))
        // At the end of its patience it stops playing along, points at you and
        // says so. Every other reaction is a face; this one is addressed.
        if face == .dizzy, Settings.petStyle == .full, roster.isEmpty,
           say(Speech(kind: .refusal, face: .dizzy,
                      until: now.addingTimeInterval(Self.refusalLifetime), holdsStill: true)) {
            detail.speak("NO")
            applyCardWidth()
            keepBubbleOnScreen()
            show()
            updateFace()
        }
    }

    // MARK: - Saying it out loud

    /// True while it speaks and for a moment after, because the last of the
    /// audio is still leaving the machine when the player reports it stopped.
    private var isTalking: Bool {
        if speaker.isSpeaking { speechEndsAfter = Date().addingTimeInterval(0.4) }
        return Date() < speechEndsAfter
    }

    @objc func toggleSpeaksAloud() {
        Settings.speaksAloud.toggle()
        speakItem.state = Settings.speaksAloud ? .on : .off
        // Says one thing when switched on, so it is obvious which voice it is.
        if Settings.speaksAloud { sayWhatsWaiting() }
    }

    /// Asked for, so it speaks whether or not the announcements are on.
    ///
    /// Only this one goes through the model. An arrival is announced the moment
    /// it lands, and waiting seconds to phrase that more prettily would be
    /// paying in the one currency an alert has.
    @objc func sayWhatsWaiting() {
        let briefing = Briefing.of(roster)
        let plain = Utterance.spoken(briefing)
        companion.quicken(for: 2)
        guard Settings.phrasesWithModel, let model = phrasingModel else {
            return speaker.say(plain)
        }
        Ollama.phrase(briefing, model: model) { phrased in
            Task { @MainActor in self.speaker.say(phrased ?? plain) }
        }
    }

    // MARK: - Listening

    /// Its own name, which is what it answers to.
    private var wakeWords: [String] { Listening.wakeWords(persona: Settings.persona.name) }

    @objc func toggleWakeWord() {
        setListening(wake: !Settings.listensForWakeWord, push: Settings.pushToTalk)
    }

    @objc func togglePushToTalk() {
        setListening(wake: Settings.listensForWakeWord, push: !Settings.pushToTalk)
    }

    /// Both ways in are one switch underneath: whether the microphone is open
    /// all the time, or only while the key is held.
    private func setListening(wake: Bool, push: Bool) {
        guard wake || push else {
            Settings.listensForWakeWord = false
            Settings.pushToTalk = false
            ears.stop()
            hotkey.unregister()
            return refreshListeningItems()
        }
        Ears.requestConsent { granted in
            Task { @MainActor in
                guard granted else {
                    Settings.listensForWakeWord = false
                    Settings.pushToTalk = false
                    self.refreshListeningItems()
                    return self.present(title: "Squawk cannot listen",
                                        message: Ears.Trouble.refused.message)
                }
                self.applyListening(wake: wake, push: push)
            }
        }
    }

    private func applyListening(wake: Bool, push: Bool) {
        Settings.listensForWakeWord = wake
        Settings.pushToTalk = push
        ears.onHeard = { [weak self] transcript, final in
            self?.heard(transcript, final: final)
        }
        if push, !hotkey.isRegistered {
            hotkey.onPress = { [weak self] in self?.startHolding() }
            hotkey.onRelease = { [weak self] in self?.stopHolding() }
            if !hotkey.register() {
                present(title: "That shortcut is taken",
                        message: "Another app already owns \(Hotkey.describedDefault), so push to talk is off. Everything else still works.")
                Settings.pushToTalk = false
            }
        }
        if !Settings.pushToTalk { hotkey.unregister() }
        if wake {
            if let trouble = ears.start(continuous: true) {
                Settings.listensForWakeWord = false
                present(title: "Squawk cannot listen", message: trouble.message)
            }
        } else if !holdingToTalk {
            ears.stop()
        }
        refreshListeningItems()
    }

    /// The lamp says an open microphone is open, whoever opened it. Squawk's
    /// own pid is left out of `PrivacyWatch` because the audio tap is not
    /// listening to the room, but this is, so it is put back in here.
    private func applyPrivacy(_ state: PrivacyState) {
        lastPrivacy = state
        var shown = state
        if ears.isRunning { shown.microphone = true }
        companion.light(shown)
    }

    /// Nothing when it is not listening, a low glow while it waits for its
    /// name, and bright for a moment once it has heard it.
    private func updateListening() {
        guard ears.isRunning else {
            companion.listening = 0
            return
        }
        if holdingToTalk {
            companion.listening = 1
            return
        }
        let since = Date().timeIntervalSince(heardNameAt)
        companion.listening = since < 2.5 ? max(0.32, 1 - since / 3.5) : 0.32
    }

    private func refreshListeningItems() {
        applyPrivacy(lastPrivacy)
        updateListening()
        wakeItem.state = Settings.listensForWakeWord ? .on : .off
        wakeItem.title = "Listen for \"\(Settings.persona.name)\""
        pushItem.state = Settings.pushToTalk ? .on : .off
    }

    private func startHolding() {
        holdingToTalk = true
        speaker.stop()
        // A held key is the whole command, so the wake word is not wanted and
        // the transcript starts empty.
        ears.stop()
        if let trouble = ears.start(continuous: false) {
            holdingToTalk = false
            NSLog("squawk: cannot listen: %@", trouble.message)
        }
    }

    private func stopHolding() {
        guard holdingToTalk else { return }
        holdingToTalk = false
        awaitingHeldSentence = true
        ears.finish()
        // The wake word waits for the held sentence to arrive rather than
        // starting on a timer: starting cancels the task that still owes us
        // that sentence, and the command was being thrown away on the way in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, awaitingHeldSentence else { return }
            awaitingHeldSentence = false
            resumeWakeWord()
        }
    }

    /// Back to listening for its name, if that is on at all.
    private func resumeWakeWord() {
        guard Settings.listensForWakeWord, !holdingToTalk, !awaitingHeldSentence else { return }
        _ = ears.start(continuous: true)
    }

    /// One transcript. Held, the whole thing is the command; otherwise only
    /// what follows its name is.
    private func heard(_ transcript: String, final: Bool) {
        let needsWake = !holdingToTalk && !awaitingHeldSentence && Settings.listensForWakeWord
        let wasHeld = awaitingHeldSentence
        if final { awaitingHeldSentence = false }
        // The held sentence has landed, so the wake word may have the
        // microphone back.
        defer { if final, wasHeld { resumeWakeWord() } }
        // It heard its name, whether or not what followed meant anything yet.
        if !needsWake || Listening.afterWake(transcript, wakeWords: wakeWords) != nil {
            heardNameAt = Date()
            updateListening()
        }
        guard let intent = Listening.command(from: transcript, final: final,
                                             wakeWords: wakeWords, requiresWake: needsWake)
        else { return }
        act(on: intent)
        // Consumed, so the same words cannot fire twice as the transcript grows.
        if !holdingToTalk, Settings.listensForWakeWord { ears.restart() }
    }

    private func act(on intent: Intent) {
        let targets = roster.entries.map { entry in
            SpokenTarget(
                id: entry.id,
                project: entry.request.project,
                risky: entry.request.awaitsDecision
                    && RiskSignal.isRisky(tool: entry.request.tool, summary: entry.request.summary),
                awaitsDecision: entry.request.awaitsDecision)
        }
        let outcome = VoiceCommand.outcome(for: intent, targets: targets,
                                           selected: ring.selectedID, pending: pendingVoice)
        switch outcome {
        case .status:
            sayWhatsWaiting()
        case .say(let line):
            pendingVoice = nil
            speaker.say(line)
        case .hush:
            pendingVoice = nil
            speaker.stop()
        case .open(let id):
            pendingVoice = nil
            ring.selectedID = id
            render()
            openPane()
        case .decide(let id, let allow):
            pendingVoice = nil
            // The same path a click takes, so a voice answer is logged, faced
            // and replied to exactly as a pressed button is.
            finish(id: id, decision: allow ? .allow : .deny,
                   reason: allow ? "Approved by voice" : "Denied by voice")
            speaker.say(allow ? "Approved." : "Denied.")
        case .confirm(let question, let id, let allow):
            pendingVoice = VoiceCommand.Pending(id: id, allow: allow, asked: Date())
            speaker.say(question)
        case .ignored:
            break
        }
    }

    @objc func togglePhrasing() {
        Settings.phrasesWithModel.toggle()
        phraseItem.state = Settings.phrasesWithModel ? .on : .off
        // Woken now rather than when someone is waiting to hear it: a model is
        // slow the first time and quick for the next few minutes.
        if Settings.phrasesWithModel, let model = phrasingModel { Ollama.warm(model) }
    }

    /// Asks Ollama what it has, so the menu can say whether this is available
    /// rather than offering something that will quietly never work.
    private func refreshLocalModels() {
        Ollama.local { models in
            Task { @MainActor in self.localModels = models }
        }
    }

    /// Picks a voice, downloading it first when it is one that has to be.
    @objc func pickVoice(_ sender: NSMenuItem) {
        guard let stored = sender.representedObject as? String else { return }
        guard stored.hasPrefix("piper:"),
              let voice = VoicePack.voice(id: String(stored.dropFirst("piper:".count)))
        else { return use(.restored(stored)) }
        guard !VoicePack.isReady(voice) else { return use(.piper(voice.id)) }
        download(voice)
    }

    private func use(_ choice: Speaker.Choice) {
        speaker.use(choice)
        Settings.voiceId = choice.stored
        speaker.say(Utterance.spoken(Briefing.of(roster)))
    }

    /// The one time download. Nothing else in the app waits on it, and
    /// cancelling genuinely stops it.
    private func download(_ voice: VoicePack.Voice) {
        guard voiceFetch == nil else { return }
        let size = VoicePack.describe(bytes: VoicePack.downloadBytes(for: voice))
        let panel = ProgressPanel(
            title: "Downloading \(voice.title)",
            message: "\(size) of speech engine and voice, kept in ~/.squawk. This happens once.")
        voicePanel = panel
        panel.show { [weak self] in self?.voiceFetch?.cancel() }
        voiceFetch = VoicePack.install(voice, progress: { fraction in
            Task { @MainActor in self.voicePanel?.progress(fraction) }
        }, finished: { trouble in
            Task { @MainActor in self.voiceArrived(voice, trouble) }
        })
    }

    private func voiceArrived(_ voice: VoicePack.Voice, _ trouble: VoicePack.Trouble?) {
        voicePanel?.close()
        voicePanel = nil
        voiceFetch = nil
        switch trouble {
        case .none:
            use(.piper(voice.id))
        case .cancelled:
            break
        case .some(let trouble):
            present(title: "Could not download \(voice.title)", message: trouble.message)
        }
    }

    /// Long enough to land, short enough not to sulk.
    static let refusalLifetime: TimeInterval = 3

    private func noteFace(_ event: FaceEvent) {
        // A reaction is over in about a second, so it gets the full frame rate
        // for one rather than being drawn at the resting rate it settles at.
        companion.quicken()
        lastFaceEvent = event
        lastFaceEventAt = Date()
        // Answering or prodding counts as attention; the nudge measures the gap
        // since one of those, not since you last glanced at it.
        lastInteractionAt = Date()
        updateFace()
    }

    /// Pointing at it wakes it. Something that stays asleep while you look
    /// straight at it is not a companion, it is a screensaver.
    private func wakeFromIdle() {
        idleSince = Date()
        updateFace()
    }

    /// The break nudge: restless after long enough with nothing answered, and
    /// it puts itself in front of you rather than waiting to be noticed.
    private func nudgeIfDue() {
        guard roster.isEmpty else { return }
        guard BreakReminder.isDue(
            minutes: Settings.breakReminderMinutes,
            lastInteraction: lastInteractionAt,
            lastNudge: lastNudgeAt
        ) else { return }
        lastNudgeAt = Date()
        lastFaceEvent = nil
        restlessUntil = Date().addingTimeInterval(12)
        show()
        updateFace()
    }

    /// The face is a function of state, not something each call site sets.
    /// How long a fortune stays up. Long enough to read twice, short enough
    /// that it is gone before you wonder how to dismiss it.
    static let fortuneLifetime: TimeInterval = 7

    /// Puts something in the slot, if nothing higher is still up, and books
    /// the one render that clears it. The face and bubble follow from state.
    @discardableResult
    private func say(_ speech: Speech) -> Bool {
        guard speaking.say(speech, at: Date()) else { return false }
        speechTimer?.invalidate()
        speechTimer = Timer.scheduledTimer(
            withTimeInterval: speech.until.timeIntervalSinceNow + 0.1, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in self?.render() }
        }
        return true
    }

    private func updateFace() {
        // Listening is not being ignored: with music on the idle clock holds.
        if companion.isHearingMusic { idleSince = Date() }
        let now = Date()
        if let until = restlessUntil, now >= until { restlessUntil = nil }
        // Risk is judged on what you are actually being shown, not on the worst
        // thing in the queue, so the face matches the command under your eyes.
        let selected = ring.selectedID.flatMap { roster.entry(id: $0) }?.request
        let decision = Mood.decide(MoodState(
            waiting: roster.count,
            awaitingDecision: roster.entries.contains { $0.request.awaitsDecision },
            risky: selected.map { $0.awaitsDecision && RiskSignal.isRisky(tool: $0.tool, summary: $0.summary) } ?? false,
            restless: restlessUntil != nil,
            speech: speaking.speech(at: now),
            hearingMusic: companion.isHearingMusic,
            lastEvent: lastFaceEvent,
            eventAge: now.timeIntervalSince(lastFaceEventAt),
            idleFor: now.timeIntervalSince(idleSince),
            modelled: Settings.petStyle == .full,
            selected: ring.selectedID != nil
        ))
        face.expression = decision.expression
        companion.grooves = decision.grooves
        companion.pose = BodyPose.pose(for: decision.expression)
        // In the full style the model paints the face onto its own screen, so
        // the flat one is never drawn; it is still what decides the expression.
        face.isHidden = !decision.showsFace
        detail.isHidden = !decision.showsCard
        bubble.isHidden = !decision.showsBubble

        let showFace = Settings.petStyle == .full || roster.isEmpty
        if showFace, panel?.isVisible == false, Settings.alwaysVisible { show() }
    }

    private func render() {
        ring.roster = roster
        let selected = ring.selectedID.flatMap { roster.entry(id: $0) }
        // Nothing waiting means nothing to act on, so the card collapses and the
        // dial is left alone in the middle rather than sat above three dead buttons.
        detail.show(selected, waiting: roster.count)
        applyCardWidth()
        keepBubbleOnScreen()
        if !roster.isEmpty || companion.isHearingMusic {
            idleSince = Date()
        } else {
            idleSince = min(idleSince, Date())
        }
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
            // It walks on from the near edge rather than appearing mid air.
            if Settings.petStyle == .full { companion.arrive(from: exitOffset()) }
        }
        fade(to: pointerInside ? 1.0 : Settings.opacity,
             duration: 0.26, curve: .easeOut)
    }

    private func hide() {
        guard !Settings.alwaysVisible else { return }
        hoverCard.hide()
        guard let panel, panel.isVisible else { return }
        // A modelled pet walks off rather than dissolving, and the window only
        // goes once it has actually left.
        guard Settings.petStyle != .full else {
            companion.leave(toward: exitOffset()) { [weak self] in self?.fadeOut() }
            return
        }
        fadeOut()
    }

    /// Which side it walks off toward: whichever screen edge it is nearer, so
    /// it never crosses the whole desktop to leave.
    private func exitOffset() -> CGFloat {
        guard let panel, let screen = NSScreen.screens.first(where: {
            $0.visibleFrame.intersects(panel.frame)
        }) ?? NSScreen.main else { return -3.4 }
        let nudge = Entrance.offset(for: panel.frame, in: screen.visibleFrame)
        return nudge.width >= 0 ? 3.4 : -3.4
    }

    private func fadeOut() {
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
        if menu === voiceMenu { return rebuildVoiceMenu() }
        speakItem.state = Settings.speaksAloud ? .on : .off
        refreshListeningItems()
        refreshLocalModels()
        let model = phrasingModel
        phraseItem.isEnabled = model != nil
        phraseItem.state = Settings.phrasesWithModel && model != nil ? .on : .off
        phraseItem.toolTip = model.map { "Rephrased by \($0), running on this Mac. Nothing leaves it." }
            ?? "Needs Ollama running with a small model: ollama pull \(Ollama.suggested)"
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
        for item in petItems {
            item.state = (item.representedObject as? String) == Settings.petStyle.rawValue ? .on : .off
        }
        for item in breakItems {
            item.state = (item.representedObject as? Int) == Settings.breakReminderMinutes ? .on : .off
        }
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

    /// The menu bar says it too, because the pet can be hidden and this is
    /// worth knowing either way.
    private func updateStatusItem(privacy state: PrivacyState) {
        lastPrivacy = state
        statusItem?.button?.toolTip = state.light?.label
        render()
    }

    func present(title: String, message: String) {
        InfoPanel.show(title: title, message: message)
    }
}

// MARK: - Size, homepage, uninstall

extension AppDelegate {
    /// Everything the pet responds to, in one place. None of it is discoverable
    /// by looking at a small robot, so it has to be written down somewhere the
    /// menu can reach.
    @objc func showHelp() {
        InfoPanel.show(title: "What Squawk Can Do", sections: [
            ("Answering",
             "A request appears in the speech bubble. Approve with Return, deny "
             + "with Escape, or open the agent's own terminal pane with O. "
             + "Session and Always remember the answer, so the same command "
             + "stops asking."),
            ("Playing",
             "Click the pet to poke it. Keep poking and it gets cross, first "
             + "orange and then red. Rub its tummy, back and forth, and it "
             + "tells you a fortune. Double tap its tummy to start a dance, and "
             + "again to stop it."),
            ("Music",
             "Turn on React to Audio and it puts headphones on whenever "
             + "something is playing, shows the spectrum on its chest, and "
             + "nods on the beat. Start a dance while music is playing and the "
             + "routine runs at the tempo of the track. macOS will ask for "
             + "permission the first time; nothing is recorded or sent "
             + "anywhere."),
            ("Looking after you",
             "Turn on Look After Me and it will remind you to rest your eyes, "
             + "sit back, stand up and get some water, and tell you when it has "
             + "got late. One thing at a time, never while something is waiting "
             + "on you, and nothing for the first twelve minutes after you sit "
             + "down."),
            ("Privacy",
             "A lamp on its chest lights orange while anything is using the "
             + "microphone and green while anything is using the camera, in "
             + "the same colours macOS uses for its own dots. This is always "
             + "on, needs no permission, and opens nothing: it asks the system "
             + "the same question the dots answer."),
            ("Living with it",
             "Point at it to wake it and bring it back to full opacity. Leave "
             + "it alone for too long, with Break Reminder on, and it gets "
             + "restless at you. It walks on and off screen rather than "
             + "appearing and vanishing."),
            ("Making it yours",
             "Character picks who is on screen. Pet Size and Transparency are "
             + "sliders in this menu, "
             + "and Pet chooses between the plain face and the full companion. "
             + "Everything is kept in ~/.squawk/config.json and can be edited "
             + "by hand."),
        ])
    }

    /// Listening is off until it is asked for. It needs the user's consent, and
    /// a desk toy has no business asking for that uninvited.
    @objc func toggleNowPlaying() {
        let wanted = !Settings.reactsToAudio
        guard wanted else {
            Settings.reactsToAudio = false
            nowPlayingItem.state = .off
            listener.stop()
            companion.hear(nil)
            return
        }
        if let trouble = listener.start() {
            Settings.reactsToAudio = false
            nowPlayingItem.state = .off
            present(title: "Cannot listen to what is playing", message: trouble.message)
            return
        }
        Settings.reactsToAudio = true
        nowPlayingItem.state = .on
    }

    private func startListeningIfWanted() {
        guard Settings.reactsToAudio else { return }
        listener.onSpectrum = { [weak self] spectrum in
            guard let self else { return }
            // A pet that hears its own voice puts headphones on to listen to
            // itself, meters its own speech and grooves to it. The tap is the
            // whole machine's output, and that includes us.
            companion.hear(isTalking ? nil : spectrum)
        }
        if let trouble = listener.start() {
            // It was on last time and is not allowed now, which is a thing the
            // user changed in System Settings rather than an error to shout
            // about. Remember it is off and say so only in the log.
            Settings.reactsToAudio = false
            nowPlayingItem.state = .off
            NSLog("squawk: not listening: %@", trouble.message)
        }
    }

    /// Looking after you is off until asked for, like everything else here
    /// that interrupts rather than waits to be looked at.
    @objc func toggleWellness() {
        Settings.wellness.toggle()
        wellnessItem.state = Settings.wellness ? .on : .off
        if Settings.wellness {
            wellnessState = Wellness.State(startedAt: Date())
            startWellnessClock()
        } else {
            wellnessTimer?.invalidate()
            wellnessTimer = nil
            speaking.stop(.wellness)
            render()
        }
    }

    private func startWellnessClock() {
        guard Settings.wellness, wellnessTimer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkWellness() }
        }
        RunLoop.main.add(timer, forMode: .common)
        wellnessTimer = timer
    }

    /// Says one thing, acts it out, and then gets out of the way.
    private func checkWellness() {
        guard Settings.wellness, Settings.petStyle == .full else { return }
        // A break long enough ends the run, so the clock is the desk's, not the app's.
        wellnessState = Wellness.resumed(
            wellnessState, lastActive: max(lastInteractionAt ?? launchedAt, lastAgentTrafficAt))
        // It waits its turn rather than talking over a fortune or a dance.
        guard speaking.speech(at: Date()) == nil, !companion.isDancing else { return }
        wellnessState.busy = !roster.isEmpty
        guard let prompt = Wellness.due(wellnessState) else { return }

        wellnessState.lastShown[prompt] = Date()
        wellnessState.lastAny = Date()
        guard say(Speech(kind: .wellness, face: prompt.face,
                         until: Date().addingTimeInterval(prompt.lifetime), holdsStill: true))
        else { return }
        detail.speak(prompt.message)
        applyCardWidth()
        keepBubbleOnScreen()
        companion.quicken(for: prompt.lifetime)
        show()
        updateFace()
    }

    @objc func pickPersona(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        let persona = Cast.named(id)
        guard persona.id != Settings.persona.id else { return }
        Settings.persona = persona
        for item in castItems {
            item.state = (item.representedObject as? String) == persona.id ? .on : .off
        }
        // The model is built around its colours, so a new one is built. Cheap:
        // it is a few dozen primitives and it happens when you pick from a menu.
        glyphCache.removeAll()
        rebuildCompanion()
        render()
    }

    @objc func pickPetStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        applyPetStyle(PetStyle.named(raw))
    }

    @objc func pickBreakReminder(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        Settings.breakReminderMinutes = minutes
        lastNudgeAt = nil
    }

    @objc func pickSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        applyDiameter(DialSize.named(raw).diameter)
    }

    @objc func openProject() { NSWorkspace.shared.open(Updates.repoURL) }

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
        listener.stop()
        privacy.stop()
        wellnessTimer?.invalidate()
        NSApp.terminate(nil)
    }
}


private extension AppDelegate {
    /// The voice list is built when it opens rather than at launch, because a
    /// download can finish while the menu is shut.
    func rebuildVoiceMenu() {
        let menu = voiceMenu
        menu.removeAllItems()
        let chosen = speaker.choice

        let system = NSMenuItem(title: "System", action: #selector(pickVoice), keyEquivalent: "")
        system.target = self
        system.representedObject = "system"
        system.state = chosen == .system(nil) ? .on : .off
        system.toolTip = "Whatever macOS speaks with. Add a better one in System Settings, Spoken Content."
        menu.addItem(system)

        // The enhanced and premium voices a user has actually downloaded from
        // Apple, named so they can be told apart. The compact default is
        // already covered by System above.
        let better = SystemVoice.english().filter { $0.quality != .default }.prefix(6)
        for voice in better {
            let item = NSMenuItem(title: voice.name, action: #selector(pickVoice), keyEquivalent: "")
            item.target = self
            item.representedObject = "system:\(voice.identifier)"
            item.state = chosen == .system(voice.identifier) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let header = NSMenuItem(title: "Neural voices", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for voice in VoicePack.catalog {
            let installed = VoicePack.isReady(voice)
            let item = NSMenuItem(title: "\(voice.title) · \(voice.note)",
                                  action: #selector(pickVoice), keyEquivalent: "")
            item.target = self
            item.representedObject = "piper:\(voice.id)"
            item.state = chosen == .piper(voice.id) ? .on : .off
            if !installed {
                item.image = Self.symbol("arrow.down.circle")
                item.toolTip = "Downloads \(VoicePack.describe(bytes: VoicePack.downloadBytes(for: voice))) once, then speaks without the network."
            }
            menu.addItem(item)
        }
    }
}
