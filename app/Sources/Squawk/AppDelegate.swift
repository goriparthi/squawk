import AppKit
import QuartzCore
import SquawkCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: SquawkPanel?
    private let ring = RingView()
    private let detail = DetailView()
    var server: RequestServer?
    /// Until when it is staying out of the way, having been shoved.
    private var shovedUntil: Date?
    /// When the behaviour file was last seen to change.
    private var behaviourSeenAt: Date?
    /// What is in front of you and since when, so nothing unasked for is said
    /// while you are still moving between windows.
    private var dwell = Dwell()
    /// When the break nudge first became due, so holding it back for a gap in
    /// the work does not turn into never saying it.
    private var nudgeDueSince: Date?
    /// Whether the agents are churning, which is not the same as anything
    /// waiting: an auto approved session never reaches the dial at all.
    var workPace = WorkPace()
    /// The one gate on what agents may say. Held here because the pet has one
    /// mouth: a limit kept by each client would be as many limits as agents.
    var speakGate = SpeakGate()
    private var roster = Roster()
    private var replies: [String: @Sendable (DecisionReply) -> Void] = [:]
    private var statusItem: NSStatusItem?
    var panelIsVisible: Bool { panel?.isVisible ?? false }
    var currentSizeName: String { DialSize.nearest(to: diameter).rawValue }
    var waitingSummary: String {
        roster.isEmpty ? "Nothing waiting" : "\(roster.count) waiting"
    }
    let visibilityItem = NSMenuItem(title: "Show Squawk", action: nil, keyEquivalent: "")
    let waitingItem = NSMenuItem(title: "Nothing waiting", action: nil, keyEquivalent: "")
    let dailyItem = NSMenuItem(title: "Check for Updates Daily", action: nil, keyEquivalent: "")
    let loginItem = NSMenuItem(title: "Open at Login", action: nil, keyEquivalent: "")
    let alwaysItem = NSMenuItem(title: "Always Show Squawk", action: nil, keyEquivalent: "")
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
    let agentSpeechItem = NSMenuItem(title: "Let Agents Speak", action: nil, keyEquivalent: "")
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
    let logItem = NSMenuItem(title: "Keep a Listening Log", action: nil, keyEquivalent: "")
    let askItem = NSMenuItem(title: "Answer My Questions", action: nil, keyEquivalent: "")
    private let asking = Asking()
    /// A week of what happened, which is what makes an answer about their own
    /// day possible at all.
    private var journal = JournalFile.load()
    /// Open while you have told it to stop asking for a few minutes.
    private var runWindow: RunWindow?
    private let runItem = NSMenuItem(title: "Let It Run", action: nil, keyEquivalent: "")
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
    /// The microphone was shut so it could answer, and goes back on when it
    /// has finished. Restarting the audio engine under a fresh utterance kills
    /// the sound: it answered every command silently because of this.
    /// A restart the wake word wants, held back until it has finished talking.
    /// Restarting the recogniser mid-utterance silences the utterance, which is
    /// one of the two ways this area has broken before.
    private var restartEarsAfterSpeaking = false
    private var startedSpeakingAt = Date.distantPast
    private var saidItCannotAnswerAt = Date.distantPast
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
    private var bubbleHeight = NSLayoutConstraint()
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
                self?.noteContext()
                self?.updateFace()
                self?.updateListening()
                self?.resumeListeningAfterSpeaking()
                self?.keepTheBeat()
                self?.closeRunWindowIfLapsed()
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
        companion.onDanceStep = { [weak self] in self?.chirp(Chirps.danceStep) }
        companion.ownTempo = Chirp.groove(for: Settings.persona.id).tempo
        companion.onTummyDoubleClick = { [weak self] in self?.startDancing() }
        companion.onPoke = { [weak self] in self?.poke() }
        companion.onShove = { [weak self] in self?.shoved() }
        // How long nothing has changed: the idle clock, which already means
        // "nothing waiting and nobody prodding".
        companion.quietFor = { [weak self] in
            guard let self else { return 0 }
            return Date().timeIntervalSince(idleSince)
        }
        background.addSubview(companion)

        bubble.onNext = { [weak self] in self?.step(forward: true) }
        bubble.onPrevious = { [weak self] in self?.step(forward: false) }
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
        bubbleHeight = bubble.heightAnchor.constraint(
            equalTo: detail.heightAnchor,
            constant: 2 * DialGeometry.bubblePadding + bubble.tailHeight
        )
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
            // Its height also carries the stack's headroom, or the peeks would
            // be drawn outside the window.
            bubble.widthAnchor.constraint(equalTo: detail.widthAnchor,
                                          constant: 2 * DialGeometry.bubblePadding),
            bubbleHeight,

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
        refreshLocalModels()
        greetOnceItHasArrived()
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
        replacement.onDanceStep = { [weak self] in self?.chirp(Chirps.danceStep) }
        replacement.ownTempo = Chirp.groove(for: Settings.persona.id).tempo
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

    /// A group parent. Four of these replaced twenty odd rows that were only
    /// ever set once, and the ones worth reaching mid-session stay at the top.
    private func group(_ title: String, _ symbol: String, _ submenu: NSMenu,
                       _ why: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = Self.symbol(symbol)
        item.toolTip = why
        item.submenu = submenu
        return item
    }

    /// For `--dump-menu`, which prints the tree so the grouping can be judged
    /// without clicking through it.
    func menuForPreview() -> NSMenu { buildMenu() }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        // Four groups, because the flat list had grown to thirty rows and
        // nothing near the bottom was ever found. What stays at the top level
        // is what gets used while an agent is running; everything that is set
        // once and left alone goes in a group.
        let look = NSMenu()
        let speech = NSMenu()
        let listening = NSMenu()
        let care = NSMenu()

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
        sizeItem.title = "Pet Size"

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

        nowPlayingItem.action = #selector(toggleNowPlaying)
        nowPlayingItem.target = self
        nowPlayingItem.image = NSImage(systemSymbolName: "headphones",
                                       accessibilityDescription: nil)
        nowPlayingItem.toolTip = "Wear headphones and show what is playing"
        nowPlayingItem.state = Settings.reactsToAudio ? .on : .off

        speakItem.action = #selector(toggleSpeaksAloud)
        speakItem.target = self
        speakItem.image = Self.symbol("waveform")
        speakItem.toolTip = "Say out loud what your agents are asking for"
        speakItem.state = Settings.speaksAloud ? .on : .off
        speech.addItem(speakItem)

        let sayItem = NSMenuItem(title: "Say What's Waiting", action: #selector(sayWhatsWaiting),
                                 keyEquivalent: "")
        sayItem.target = self
        sayItem.image = Self.symbol("bubble.left.and.text.bubble.right")
        speech.addItem(sayItem)

        agentSpeechItem.action = #selector(toggleAgentSpeech)
        agentSpeechItem.target = self
        agentSpeechItem.image = Self.symbol("quote.bubble")
        agentSpeechItem.toolTip = "Let an agent say a line through the pet, with the speak tool. "
            + "Rate limited and redacted, and it can never approve anything."
        agentSpeechItem.state = Settings.agentsMaySpeak ? .on : .off
        speech.addItem(agentSpeechItem)

        wakeItem.action = #selector(toggleWakeWord)
        wakeItem.target = self
        wakeItem.image = Self.symbol("ear")
        listening.addItem(wakeItem)

        pushItem.action = #selector(togglePushToTalk)
        pushItem.target = self
        pushItem.image = Self.symbol("mic")
        pushItem.toolTip = "Hold \(Hotkey.describedDefault) anywhere and say what you want"
        pushItem.state = Settings.pushToTalk ? .on : .off
        listening.addItem(pushItem)

        runItem.submenu = buildRunMenu()
        runItem.image = Self.symbol("figure.run")
        runItem.toolTip = "Stop asking for a few minutes. Anything risky still waits for you."
        menu.addItem(runItem)

        let weekItem = NSMenuItem(title: "This Week", action: #selector(showHistory),
                                  keyEquivalent: "")
        weekItem.target = self
        weekItem.image = Self.symbol("list.bullet.rectangle")
        weekItem.toolTip = "What your agents asked for and what you answered, kept for seven days"
        // Holding option offers to erase it instead, which keeps a destructive
        // thing out of the way without hiding it.
        let forgetItem = NSMenuItem(title: "Forget This Week", action: #selector(forgetWeek),
                                    keyEquivalent: "")
        forgetItem.target = self
        forgetItem.image = Self.symbol("trash")
        forgetItem.isAlternate = true
        forgetItem.keyEquivalentModifierMask = .option
        menu.addItem(weekItem)
        menu.addItem(forgetItem)

        askItem.action = #selector(toggleAnswering)
        askItem.target = self
        askItem.image = Self.symbol("questionmark.bubble")
        askItem.toolTip = "Answers the time, the weather and whatever else you ask, using a model on this Mac"
        askItem.state = Settings.answersQuestions ? .on : .off
        listening.addItem(askItem)

        logItem.action = #selector(toggleListeningLog)
        logItem.target = self
        logItem.image = Self.symbol("doc.text.magnifyingglass")
        logItem.toolTip = "Keeps what it heard in ~/.squawk/listening.log, so a command that went nowhere can be explained"
        logItem.state = Settings.logsListening ? .on : .off
        listening.addItem(logItem)

        phraseItem.action = #selector(togglePhrasing)
        phraseItem.target = self
        phraseItem.image = Self.symbol("text.bubble")
        phraseItem.state = Settings.phrasesWithModel ? .on : .off
        speech.addItem(phraseItem)

        let voiceParent = NSMenuItem(title: "Voice", action: nil, keyEquivalent: "")
        voiceParent.image = Self.symbol("person.wave.2")
        voiceMenu.delegate = self
        voiceParent.submenu = voiceMenu
        speech.addItem(voiceParent)

        wellnessItem.action = #selector(toggleWellness)
        wellnessItem.target = self
        wellnessItem.image = NSImage(systemSymbolName: "figure.cooldown",
                                     accessibilityDescription: nil)
        wellnessItem.toolTip = "Eye breaks, posture, water, and a word when it gets late"
        wellnessItem.state = Settings.wellness ? .on : .off
        care.addItem(wellnessItem)

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
        care.addItem(breakParent)
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
        opacityItem.title = "Opacity"
        opacityControl = opacity

        // The two sliders together, then the presets that set the same thing,
        // then what the pet actually is. They used to sit at opposite ends of
        // the list with twenty rows between them.
        for row in [sizeItem, opacityItem, NSMenuItem.separator(), sizeParent,
                    NSMenuItem.separator(), petParent, castParent,
                    NSMenuItem.separator(), nowPlayingItem] {
            look.addItem(row)
        }

        menu.addItem(.separator())
        menu.addItem(group("Appearance", "paintbrush", look,
                           "Size, opacity, style and which of the cast it is"))
        menu.addItem(group("Speech", "waveform", speech,
                           "What it says out loud, and in whose voice"))
        menu.addItem(group("Listening", "ear", listening,
                           "The microphone, and what it does with what it hears"))
        menu.addItem(group("Looking After You", "figure.cooldown", care,
                           "Eye breaks, posture, and a word when it gets late"))
        menu.addItem(.separator())

        let updates = makeItem("Check for Updates Now", #selector(checkForUpdates),
                               symbol: "arrow.triangle.2.circlepath")
        updates.keyEquivalent = "u"
        updates.keyEquivalentModifierMask = [.command]
        menu.addItem(updates)
        dailyItem.target = self
        dailyItem.image = Self.symbol("calendar")
        dailyItem.action = #selector(toggleDailyChecks)
        loginItem.target = self
        loginItem.image = Self.symbol("person.badge.key")
        loginItem.action = #selector(toggleLoginItem)

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
        let settings = makeItem("Open Settings File", #selector(openConfig), symbol: "doc.text")
        settings.toolTip = Settings.configPath
        let behaviour = makeItem("Edit Model Instructions", #selector(openBehaviour),
                                 symbol: "text.book.closed")
        behaviour.toolTip = "What the local model is told, in a file Squawk re-reads as you save it" 
        rememberedItem.image = Self.symbol("checklist")

        // Set once and then left alone, or wanted exactly once. Checking for
        // updates stays outside because it is the one here anybody reaches for.
        let advanced = NSMenu()
        for row in [dailyItem, loginItem, NSMenuItem.separator(), settings, behaviour, rememberedItem,
                    NSMenuItem.separator(),
                    makeItem("Uninstall Squawk\u{2026}", #selector(uninstall), symbol: "trash")] {
            advanced.addItem(row)
        }
        menu.addItem(group("Advanced", "gearshape", advanced,
                           "Startup, the settings file, remembered answers and uninstalling"))
        menu.addItem(.separator())

        menu.addItem(makeItem("What Squawk Can Do\u{2026}", #selector(showHelp),
                              symbol: "questionmark.circle"))
        menu.addItem(homeItem)
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
        } speaking: { [weak self] ask, reply in
            Task { @MainActor in self?.speakForAgent(ask, reply: reply) }
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
        // So does an open window, unless this is the sort of thing it will not
        // cover, which still stops and waits however little time is left.
        if request.awaitsDecision,
           runWindow?.covers(tool: request.tool, summary: request.summary) == true {
            note(.approved, request.project, "\(request.tool): \(request.summary)")
            reply(DecisionReply(id: request.id, decision: .allow, reason: "Squawk was let run"))
            return
        }
        // Arriving while it was asleep is a start; arriving while it was awake
        // is just work.
        if roster.isEmpty, Date().timeIntervalSince(idleSince) >= FaceMood.sleepAfter {
            noteFace(.startled)
        }
        replies[request.id] = reply
        roster.add(request)
        note(.arrived, request.project, "\(request.tool): \(request.summary)")
        if Settings.speaksAloud {
            speaker.say(Utterance.arrival(Briefing.item(for: request)))
        }
        if ring.selectedID == nil { ring.selectedID = request.id }
        // Something arriving brings it back whether or not it was shoved, so
        // the shove is spent rather than left to hide it again afterwards.
        shovedUntil = nil
        render()
        show()
    }

    /// The hook behind this arc is gone, so nothing is listening for a decision.
    private func drop(_ id: String, reacting: Bool = true) {
        guard roster.entry(id: id) != nil else { return }
        if reacting { noteFace(.abandoned) }
        replies.removeValue(forKey: id)
        // Asked before it goes, so the answer can prefer the same session.
        let following = roster.next(after: id)
        roster.remove(id: id)
        ring.selectedID = following
        render()
        if roster.isEmpty { hide() }
    }

    /// Says a line an agent handed over through the MCP speak tool.
    ///
    /// It may never decide anything, and it is the one thing on this socket
    /// whose words come from outside: whatever is driving the agent chose them,
    /// so consent is explicit, the rate is capped and the text is redacted
    /// before it is drawn or spoken.
    private func speakForAgent(
        _ ask: SpeakRequest, reply: @escaping @Sendable (SpeakReply) -> Void
    ) {
        lastAgentTrafficAt = Date()
        guard Settings.agentsMaySpeak else {
            return reply(SpeakReply(
                spoke: false,
                detail: "Squawk is not letting agents speak. "
                    + "Turn on Let Agents Speak in its menu."
            ))
        }
        switch speakGate.admit(ask.text, at: Date()) {
        case .refused(let why):
            reply(SpeakReply(spoke: false, detail: why))
        case .say(let line):
            guard sayForAgent(line) else {
                return reply(SpeakReply(
                    spoke: false,
                    detail: "Squawk was saying something of its own, so nothing was said."
                ))
            }
            note(.spoke, ask.project, line)
            reply(SpeakReply(spoke: true, detail: "Said out loud: \(line)"))
        }
    }

    /// Its own path rather than `speakAloud`, because this one may be refused:
    /// an agent must not talk over a refusal or a wellness prompt, and it has to
    /// be told when it did not speak.
    private func sayForAgent(_ line: String) -> Bool {
        guard say(Speech(kind: .agent, face: .happy,
                         until: Date().addingTimeInterval(replyTime(for: line))))
        else { return false }
        companion.quicken(for: 2)
        // The bubble is the full style's; the dial has nowhere to put the words.
        if Settings.petStyle == .full {
            detail.speak(line)
            applyCardWidth()
            keepBubbleOnScreen()
            show()
            updateFace()
        }
        speakOnly(line)
        return true
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
        if let entry = roster.entry(id: id) {
            note(decision == .allow ? .approved : .denied,
                 entry.request.project, entry.request.summary)
        }
        // Clearing the last of several is relief; clearing one is just an answer.
        let wasBacklog = roster.count > 1
        noteFace(decision == .allow ? .approved : .denied)
        if let reply = replies.removeValue(forKey: id) {
            reply(DecisionReply(id: id, decision: decision, reason: reason))
        }
        // Asked before the entry goes, because the answer is which session it
        // belonged to. Afterwards there is nothing left to ask about.
        let following = roster.next(after: id)
        roster.remove(id: id)
        // Clearing the last of several is relief, and it replaces the plain
        // acknowledgement rather than queueing behind it.
        if wasBacklog, roster.isEmpty { noteFace(.relieved) }
        // Another call from the same agent first. Answering is only half the
        // loop; being thrown to a different project on every click is the half
        // that costs you.
        ring.selectedID = following
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
        // Sampled here rather than on the face clock: the pace is judged over
        // a minute and a half, so reading it three times a second would be
        // ninety nine readings that cannot have changed.
        workPace.sample(arrivals: journal.arrivals())
        rereadBehaviourIfChanged()
        returnIfShoveHasLapsed()

        let expired = roster.expire(fallback: fallbackLifetime)
        guard !expired.isEmpty else { return }
        for entry in expired { replies.removeValue(forKey: entry.id) }
        ring.selectedID = roster.grouped.first?.id
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

    /// How many cards are behind the one being read, and what the next one is.
    ///
    /// Only in the modelled style: the drawn one has the ring, which says the
    /// same thing better, and the card sits inside the head there with nowhere
    /// for a stack to go.
    private func applyStack(behind selected: Roster.Entry?) {
        let modelled = Settings.petStyle == .full
        let depth = modelled && selected != nil ? max(0, roster.count - 1) : 0
        bubble.stackDepth = depth
        if depth > 0, let selected,
           let next = roster.after(selected.id).flatMap({ roster.entry(id: $0) }) {
            // The same rule the arcs used: amber is a decision, blue is a
            // session that only wants you.
            bubble.stackTint = next.request.awaitsDecision ? Palette.waiting : Palette.running
        }
        // The peeks live above the card, so the bubble has to be that much
        // taller or they are drawn outside the window.
        let headroom = bubble.headroom
        let wanted = 2 * DialGeometry.bubblePadding + bubble.tailHeight + headroom
        if bubbleHeight.constant != wanted { bubbleHeight.constant = wanted }
    }

    /// One card along the stack, which is the modelled style's answer to
    /// clicking a different arc.
    private func step(forward: Bool) {
        guard let current = ring.selectedID, roster.count > 1 else { return }
        guard let next = forward ? roster.after(current) : roster.before(current),
              next != current
        else { return }
        select(next)
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
            let title = track?.title ?? tab ?? appName
            detail.showNowPlaying(title: title,
                                  artist: track?.artist,
                                  detail: lines.joined(separator: "  ·  "),
                                  artwork: track?.artwork)
            applyCardWidth()
            keepBubbleOnScreen()
            show()
            updateFace()
            if Settings.speaksAloud, let title {
                let artist: String? = track?.artist
                speakOnly(artist.map { "\(title) by \($0)." } ?? "\(title).")
            }
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
        // Read out too, when it has been asked to speak at all. A fortune is
        // the one thing it says entirely for the fun of it.
        if Settings.speaksAloud { speakOnly(text) }
    }

    /// Tapped its tummy once: a wink and a wiggle, never a poke, so tickling
    /// it never makes it cross.
    private func tickled() {
        lastInteractionAt = Date()
        restlessUntil = nil
        chirp(Chirps.giggle)
        noteFace(.poked(.wink))
    }

    /// The loop runs only while it is actually dancing to nothing else. A
    /// track starting, or the routine ending, takes it off.
    private func keepTheBeat() {
        guard Chirps.isBeating else { return }
        if !companion.isDancing || companion.isHearingMusic || !Settings.makesSounds {
            Chirps.stopBeat()
        }
    }

    /// Anything the pet says with a noise goes through here. It keeps quiet
    /// over music, which it is already dancing to, and over its own voice.
    private func chirp(_ play: () -> Void) {
        guard !companion.isHearingMusic, !speaker.isSpeaking else { return }
        play()
    }

    /// Double tapped its tummy, which starts the routine, and again to stop it.
    private func startDancing() {
        lastInteractionAt = Date()
        restlessUntil = nil
        speaking.stop()
        Chirps.resetDance()
        noteFace(.poked(.happy))
        companion.toggleDance()
        // Its own beat, but only when nothing else is playing: a pet that lays
        // a drum loop over your record is not dancing with you.
        if companion.isDancing, !companion.isHearingMusic {
            Chirps.startBeat(for: Settings.persona.id)
        } else {
            Chirps.stopBeat()
        }
        render()
    }

    private func poke() {
        chirp(Chirps.poke)
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
            // One word, and it is not asking. Said slower and lower than
            // anything else it says, with a tone giving up underneath it.
            detail.speak("NO")
            applyCardWidth()
            keepBubbleOnScreen()
            show()
            updateFace()
            chirp(Chirps.grumble)
            if Settings.speaksAloud { speakOnly("No!", firmly: true) }
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

    @objc func toggleAgentSpeech() {
        Settings.agentsMaySpeak.toggle()
        agentSpeechItem.state = Settings.agentsMaySpeak ? .on : .off
    }

    /// How long a hello stays up. Long enough to read, short enough that it is
    /// gone before it needs dismissing.
    static let greetingLifetime: TimeInterval = 7

    /// Says hello, once, after the pet has walked on. Different every launch:
    /// the last one is remembered so it cannot be repeated.
    private func greetOnceItHasArrived() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, Settings.petStyle == .full, roster.isEmpty else { return }
            // Waits until you have settled somewhere. Launching Squawk and then
            // going straight back to the editor should not be greeted at: the
            // same line, once you have stopped moving, is a remark rather than
            // an interruption. It keeps trying on the face clock.
            guard dwell.mayVolunteer() else { return greetOnceItHasArrived() }
            let hello = Greeting.next(after: Settings.lastGreeting)
            Settings.lastGreeting = hello
            guard say(Speech(kind: .greeting, face: .happy,
                             until: Date().addingTimeInterval(Self.greetingLifetime)))
            else { return }
            detail.speak(hello)
            applyCardWidth()
            keepBubbleOnScreen()
            show()
            updateFace()
            // Said out loud only when it has been asked to speak at all.
            if Settings.speaksAloud { speaker.say(hello) }
            // After the greeting, never before: the warm up would otherwise be
            // competing with the one line somebody is actually listening to.
            warmVoice()
        }
    }

    /// Renders the lines it is sure to say, so the first one is not the slow
    /// one. Measured at 520 to 730 ms a line, warm, which is cheap enough that
    /// this is about the first line after a launch and nothing more.
    private func warmVoice() {
        speaker.warm(Warmup.lines)
    }

    /// Everything it says goes through here, so the log shows not only what it
    /// meant to say but whether any sound actually started.
    /// How long a spoken answer stays on screen. Long enough to read after
    /// the sound has gone, which is the point of putting it there.
    static let replyLifetime: TimeInterval = 6
    /// A long answer needs longer on screen than "Nothing waiting".
    private func replyTime(for text: String) -> TimeInterval {
        min(20, max(Self.replyLifetime, Double(text.count) / 12))
    }

    private func speakAloud(_ text: String) {
        // Shown as well as said. Spoken on its own, an answer is a second of
        // quiet speech from whichever device happens to be the output, and
        // there is no sign at all that it understood you.
        if Settings.petStyle == .full,
           say(Speech(kind: .reply, face: .happy,
                      until: Date().addingTimeInterval(replyTime(for: text)))) {
            detail.speak(text)
            applyCardWidth()
            keepBubbleOnScreen()
            show()
            updateFace()
        }
        speakOnly(text)
    }

    /// Says something that is already on screen by some other route. Anything
    /// the pet says aloud goes through here, whatever put it in the bubble.
    private func speakOnly(_ text: String, firmly: Bool = false) {
        // The ears stay open through an utterance so it can be cut off, which
        // is the only way to stop a long answer without reaching for the
        // keyboard. What is heard during one may do exactly one thing: stop.
        //
        // This is survivable only because the built-in microphone cancels the
        // Mac's own speakers, so on the common setup it does not hear itself.
        // On speakers it might, which is why the rule is "stop, and nothing
        // else": the worst a transcript of its own voice can do is silence.
        //
        // It must not restart the engine here. Restarting the recogniser a
        // moment after an utterance is queued silences the utterance, which is
        // one of the two ways this area has broken before.
        startedSpeakingAt = Date()
        if ears.isRunning, !holdingToTalk { restartEarsAfterSpeaking = true }
        // Said the way people say them: the terms it reads out most are the
        // ones every synthesiser is worst at.
        speaker.say(Speakable.spoken(text), firmly: firmly)
        ListeningLog.note("saying: \(text)")
    }

    /// The ears are open through the utterance, so there is nothing to resume;
    /// what waits is the *restart* the wake word needs, which would have cut
    /// the utterance off mid-word had it run during one.
    private func resumeListeningAfterSpeaking() {
        guard restartEarsAfterSpeaking else { return }
        // A synthesiser takes a moment to report itself as speaking, so the
        // gap is given a floor rather than trusting the first reading.
        guard Date().timeIntervalSince(startedSpeakingAt) > 1.0, !speaker.isSpeaking else { return }
        restartEarsAfterSpeaking = false
        guard !holdingToTalk, Settings.listensForWakeWord, ears.isRunning else { return }
        // Clears the rolling transcript. A continuous session keeps everything
        // said near the machine, so anything it caught of its own voice would
        // otherwise sit there and be read again as the transcript grows.
        ears.restart()
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
            return speakAloud(plain)
        }
        Ollama.phrase(briefing, model: model) { phrased in
            Task { @MainActor in self.speakAloud(phrased ?? plain) }
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
        ears.onDeviceChanged = { [weak self] recovered in
            ListeningLog.note("microphone changed; listening again: \(recovered)")
            guard let self, !recovered else { return }
            // It cannot hear, so it must stop saying that it can.
            applyPrivacy(lastPrivacy)
            updateListening()
        }
        if push, !hotkey.isRegistered {
            hotkey.onPress = { [weak self] in self?.startHolding() }
            hotkey.onRelease = { [weak self] in self?.stopHolding() }
            let registered = hotkey.register()
            ListeningLog.note("hotkey \(Hotkey.describedDefault) registered: \(registered)")
            if !registered {
                present(title: "That shortcut is taken",
                        message: "Another app already owns \(Hotkey.describedDefault), so push to talk is off. Everything else still works.")
                Settings.pushToTalk = false
            }
        }
        if !Settings.pushToTalk { hotkey.unregister() }
        ListeningLog.note("listening set: wake \(wake), push \(Settings.pushToTalk), permitted \(Ears.isPermitted)")
        if wake {
            if let trouble = ears.start(continuous: true) {
                ListeningLog.note("wake word could not start: \(trouble.message)")
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
        ListeningLog.note("hotkey down")
        holdingToTalk = true
        speaker.stop()
        // A held key is the whole command, so the wake word is not wanted and
        // the transcript starts empty.
        ears.stop()
        if let trouble = ears.start(continuous: false) {
            holdingToTalk = false
            ListeningLog.note("cannot listen while held: \(trouble.message)")
            NSLog("squawk: cannot listen: %@", trouble.message)
        }
    }

    private func stopHolding() {
        ListeningLog.note("hotkey up (holding: \(holdingToTalk))")
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

    /// Cuts off whatever it is saying, in both senses: the sound stops and the
    /// bubble goes with it. Leaving the words on screen after being told to be
    /// quiet is half an answer. `speaker.stop()` also disowns a line still
    /// being synthesised, so a Piper render landing a second later does not
    /// play over the silence that was asked for.
    private func hush() {
        speaker.stop()
        speaking.stop()
        render()
    }

    /// Back to listening for its name, if that is on at all.
    private func resumeWakeWord() {
        guard Settings.listensForWakeWord, !holdingToTalk, !awaitingHeldSentence
        else { return }
        if let trouble = ears.start(continuous: true) {
            ListeningLog.note("could not start listening again: \(trouble.message)")
        }
    }

    /// One transcript. Held, the whole thing is the command; otherwise only
    /// what follows its name is.
    private func heard(_ transcript: String, final: Bool) {
        // Talking over it may only silence it. Acted on from a partial,
        // deliberately: waiting for the end of the sentence to honour "stop"
        // means it has already finished saying the thing you interrupted.
        if speaker.isSpeaking, !holdingToTalk {
            guard Listening.interruption(from: transcript, wakeWords: wakeWords) != nil
            else { return }
            ListeningLog.note("interrupted mid-sentence | \(transcript.suffix(60))")
            hush()
            return
        }
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
        let intent = Listening.command(from: transcript, final: final,
                                       wakeWords: wakeWords, requiresWake: needsWake)
        if final || intent != nil {
            ListeningLog.note("heard [\(final ? "final" : "partial")] needsWake \(needsWake) "
                + "wake \(wakeWords.first ?? "?") | \(transcript.suffix(Listening.tailLimit)) "
                + "| intent: \(intent.map { "\($0)" } ?? "none")")
        }
        guard let intent else { return }
        act(on: intent)
        // Consumed, so the same words cannot fire twice as the transcript
        // grows. If answering it started it talking, the restart waits until
        // the utterance has finished rather than cutting it off mid-word.
        if !holdingToTalk, Settings.listensForWakeWord {
            if speaker.isSpeaking {
                restartEarsAfterSpeaking = true
            } else {
                ears.restart()
            }
        }
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
        ListeningLog.note("did: \(outcome) (waiting: \(targets.count))")
        switch outcome {
        case .status:
            sayWhatsWaiting()
        case .say(let line):
            pendingVoice = nil
            speakAloud(line)
        case .hush:
            pendingVoice = nil
            hush()
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
            speakAloud(allow ? "Approved." : "Denied.")
        case .confirm(let question, let id, let allow):
            pendingVoice = VoiceCommand.Pending(id: id, allow: allow, asked: Date())
            speakAloud(question)
        case .answer(let question):
            pendingVoice = nil
            answerQuestion(question)
        case .ignored:
            break
        }
    }

    /// Turning it off deletes what is already there: leaving a record of
    /// someone's speech behind after they asked for it to stop is not a choice
    /// to make on their behalf.
    @objc func toggleListeningLog() {
        Settings.logsListening.toggle()
        logItem.state = Settings.logsListening ? .on : .off
        if !Settings.logsListening { ListeningLog.clear() }
    }

    private func buildRunMenu() -> NSMenu {
        let menu = NSMenu()
        for length in RunWindow.lengths {
            let item = NSMenuItem(title: "For \(RunWindow.describe(length: length))",
                                  action: #selector(letItRun), keyEquivalent: "")
            item.target = self
            item.representedObject = length
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let stop = NSMenuItem(title: "Stop", action: #selector(stopRunning), keyEquivalent: "")
        stop.target = self
        menu.addItem(stop)
        return menu
    }

    /// Broad permission that expires, which is a better bargain than the
    /// permanent kind granted in a hurry. It says so on the way in and on the
    /// way out, because an open window nobody remembers is the failure here.
    @objc func letItRun(_ sender: NSMenuItem) {
        guard let length = sender.representedObject as? TimeInterval else { return }
        runWindow = RunWindow(length: length)
        note(.approved, nil, "let it run for \(RunWindow.describe(length: length))")
        announce("Running for \(RunWindow.describe(length: length)). "
            + "Anything risky still waits for you.")
    }

    @objc func stopRunning() {
        guard runWindow != nil else { return }
        runWindow = nil
        announce("Back to asking.")
    }

    /// Closes the window the moment it lapses, and says so: it has been
    /// answering for you, and you should know when it stops.
    private func checkRunWindow() {
        guard let window = runWindow, !window.isOpen() else {
            runItem.title = runWindow == nil ? "Let It Run" : runItem.title
            return
        }
        runItem.title = "Let It Run (\(window.described()))"
    }

    private func closeRunWindowIfLapsed() {
        guard let window = runWindow, !window.isOpen() else { return }
        runWindow = nil
        runItem.title = "Let It Run"
        announce("That is time. Back to asking.")
    }

    /// Said and shown, when it matters enough to interrupt whatever is up.
    private func announce(_ line: String) {
        guard Settings.petStyle == .full else { return }
        if say(Speech(kind: .reply, face: .alert,
                      until: Date().addingTimeInterval(Self.replyLifetime))) {
            detail.speak(line)
            applyCardWidth()
            keepBubbleOnScreen()
            show()
            updateFace()
        }
        if Settings.speaksAloud { speakOnly(line) }
    }

    @objc func showHistory() {
        HistoryWindow.shared.show(journal)
    }

    /// Theirs to erase. A week of what someone approved is a record of their
    /// work, and keeping it after they have asked it gone is not a decision to
    /// make for them.
    @objc func forgetWeek() {
        let alert = NSAlert()
        alert.messageText = "Forget this week?"
        alert.informativeText = "Everything in This Week goes, including what your agents "
            + "asked for and what you answered. It cannot be brought back."
        alert.addButton(withTitle: "Forget")
        alert.addButton(withTitle: "Keep")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        journal = Journal()
        JournalFile.erase()
        HistoryWindow.shared.refresh(journal)
    }

    @objc func toggleAnswering() {
        Settings.answersQuestions.toggle()
        askItem.state = Settings.answersQuestions ? .on : .off
        asking.forget()
        if Settings.answersQuestions, let model = phrasingModel { Ollama.warm(model) }
        updateModelMark()
    }

    /// Said at most this often, so a pet that cannot answer does not repeat
    /// itself at everyone who talks near it.
    static let cannotAnswerEvery: TimeInterval = 120

    /// Writes one thing down and keeps the file trimmed to a week.
    private func note(_ kind: Journal.Entry.Kind, _ project: String?, _ text: String) {
        journal.add(Journal.Entry(at: Date(), kind: kind, project: project,
                                  text: ToolSummary.truncate(text, to: 120)))
        JournalFile.save(journal)
        HistoryWindow.shared.refresh(journal)
    }

    /// Everything true right now, for a model that knows none of it.
    private var situation: String {
        Situation.summary(Situation.State(
            place: Settings.weatherPlace.isEmpty ? Weather.placeFromTimeZone : Settings.weatherPlace,
            briefing: Briefing.of(roster),
            journal: journal,
            atDeskFor: Wellness.atDesk(since: wellnessState.startedAt),
            playing: companion.isHearingMusic))
    }

    private func answerQuestion(_ question: String) {
        guard Settings.answersQuestions else {
            // Understood, and then nothing at all, is the worst thing it can
            // do: it looks broken rather than switched off. It says which.
            guard Date().timeIntervalSince(saidItCannotAnswerAt) > Self.cannotAnswerEvery
            else { return }
            saidItCannotAnswerAt = Date()
            ListeningLog.note("understood a question but Answer My Questions is off")
            return speakAloud("I heard you, but answering questions is switched off. "
                + "Turn on Answer My Questions in my menu.")
        }
        note(.asked, nil, question)
        asking.answer(question, model: phrasingModel,
                      place: Settings.weatherPlace.isEmpty ? nil : Settings.weatherPlace,
                      situation: situation) { spoken in
            Task { @MainActor in
                self.note(.answered, nil, spoken)
                self.speakAloud(spoken)
            }
        }
    }

    @objc func togglePhrasing() {
        Settings.phrasesWithModel.toggle()
        phraseItem.state = Settings.phrasesWithModel ? .on : .off
        // Woken now rather than when someone is waiting to hear it: a model is
        // slow the first time and quick for the next few minutes.
        if Settings.phrasesWithModel, let model = phrasingModel { Ollama.warm(model) }
        updateModelMark()
    }

    /// Asks Ollama what it has, so the menu can say whether this is available
    /// rather than offering something that will quietly never work.
    private func refreshLocalModels() {
        Ollama.local { models in
            Task { @MainActor in
                self.localModels = models
                self.updateModelMark()
            }
        }
    }

    /// Worn while a model is configured to do the work, rather than only during
    /// the moment one is answering. A mark that lights for the 650ms a reply
    /// takes is a flicker, not a badge. It still says something true: switch
    /// both features off and it goes dark, because then nothing is thinking for
    /// it, and it stays dark on a Mac with no model to choose.
    private func updateModelMark() {
        let wanted = Settings.phrasesWithModel || Settings.answersQuestions
        companion.showsModelMark = wanted && phrasingModel != nil
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
        // The cache is keyed by voice as well as text, so a new voice starts
        // with none of these and would pay for each of them once.
        warmVoice()
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
        // When it first became due, so holding off for a gap in the work can
        // be bounded rather than open ended.
        if BreakReminder.isWaitingForAGap(
            minutes: Settings.breakReminderMinutes,
            lastInteraction: lastInteractionAt,
            lastNudge: lastNudgeAt
        ) {
            if nudgeDueSince == nil { nudgeDueSince = Date() }
        } else {
            nudgeDueSince = nil
        }
        guard BreakReminder.isDue(
            minutes: Settings.breakReminderMinutes,
            lastInteraction: lastInteractionAt,
            lastNudge: lastNudgeAt,
            working: workPace.isWorking,
            dueSince: nudgeDueSince
        ) else { return }
        nudgeDueSince = nil
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

    /// Thrown out of the way rather than carried there, which is the one
    /// gesture that means "you are in my way" without having to aim at a gap.
    ///
    /// Never while something is waiting on a decision: a gesture must not be
    /// able to hide the thing this app exists to put in front of you. Dragging
    /// it still works, so there is always a way to move it.
    private func shoved() {
        guard roster.isEmpty else { return }
        noteFace(.startled)
        shovedUntil = Date().addingTimeInterval(Shove.staysAwayFor)
        // Past the pin, deliberately. Asking for it to be always visible and
        // then throwing it across the desk is the later instruction.
        companion.leave(toward: exitOffset()) { [weak self] in self?.fadeOut() }
    }

    /// Back once it has been out of the way long enough, but only if it would
    /// have been on screen anyway.
    private func returnIfShoveHasLapsed() {
        guard let until = shovedUntil, Date() >= until else { return }
        shovedUntil = nil
        guard Settings.alwaysVisible, roster.isEmpty else { return }
        show()
    }

    /// Re-reads the behaviour file when it has actually changed.
    ///
    /// Polled on the sweep rather than watched. An editor saving a file usually
    /// replaces it rather than writing into it, which invalidates a file
    /// descriptor watch and leaves it silently dead; stat-ing one small file
    /// every five seconds cannot go stale that way.
    private func rereadBehaviourIfChanged() {
        let path = BehaviourRules.path()
        let stamp = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate]
        let seen = (stamp as? Date) ?? .distantPast
        guard seen != behaviourSeenAt else { return }
        behaviourSeenAt = seen
        Settings.reloadBehaviour()
    }

    /// What is frontmost, for the dwell gate. The bundle identifier rather than
    /// the name: two windows of one app are one context, and switching between
    /// them is not the kind of moving about this is watching for.
    private func noteContext() {
        dwell.entered(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
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
            selected: ring.selectedID != nil,
            working: workPace.isWorking
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
        if showFace, panel?.isVisible == false, Settings.alwaysVisible,
           shovedUntil == nil { show() }
    }

    private func render() {
        ring.roster = roster
        let selected = ring.selectedID.flatMap { roster.entry(id: $0) }
        // Nothing waiting means nothing to act on, so the card collapses and the
        // dial is left alone in the middle rather than sat above three dead buttons.
        detail.show(selected, waiting: roster.count,
                    otherAgents: ring.selectedID.map(roster.otherSessions(than:)) ?? 0,
                    place: selected.flatMap { roster.place(of: $0.id) }.map { $0.index + 1 })
        applyStack(behind: selected)
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
        visibilityItem.title = (panel?.isVisible ?? false) ? "Hide Squawk" : "Show Squawk"
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
        checkRunWindow()
        speakItem.state = Settings.speaksAloud ? .on : .off
        agentSpeechItem.state = Settings.agentsMaySpeak ? .on : .off
        refreshListeningItems()
        logItem.state = Settings.logsListening ? .on : .off
        askItem.state = Settings.answersQuestions ? .on : .off
        refreshLocalModels()
        // The mark stands where a model is genuinely doing the work, and
        // nowhere else: a badge for something that is not running is a boast.
        let mark = phrasingModel != nil ? OllamaMark.image(size: 13) : nil
        phraseItem.image = mark ?? Self.symbol("text.bubble")
        askItem.image = mark ?? Self.symbol("questionmark.bubble")
        let model = phrasingModel
        phraseItem.isEnabled = model != nil
        phraseItem.state = Settings.phrasesWithModel && model != nil ? .on : .off
        phraseItem.toolTip = model.map { "Rephrased by \($0), running on this Mac. Nothing leaves it." }
            ?? "Needs Ollama running with a small model: ollama pull \(Ollama.suggested)"
        dailyItem.state = Settings.checksForUpdates ? .on : .off
        // The row says what it does; when it happens is detail, and a title
        // that changes as the schedule does is a row you have to read twice.
        dailyItem.toolTip = "Checks at "
            + Settings.checkTimes.map(\.text).joined(separator: " and ")
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
        visibilityItem.title = visible ? "Hide Squawk" : "Show Squawk"
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
        // A break long enough ends the run, so the clock is the desk's, not the
        // app's. Presence is the Mac's own input: judged by pokes and agent
        // traffic alone, an hour of quiet typing read as an empty chair and
        // restarted the run on every check, so nothing was ever due.
        wellnessState = Wellness.resumed(wellnessState, lastActive: Presence.lastInput)
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
        // A new character brings its own groove, so a routine already running
        // changes over rather than finishing in somebody else's tempo.
        if Chirps.isBeating {
            Chirps.stopBeat()
            Chirps.resetDance()
            Chirps.startBeat(for: persona.id)
        }
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

    /// Opens the behaviour file, writing the template first if it has never
    /// existed. A blank page and a guess at the headings is not an invitation
    /// to edit anything.
    @objc func openBehaviour() {
        let path = BehaviourRules.path()
        if !FileManager.default.fileExists(atPath: path) {
            let text = BehaviourRules.template(phrasing: Phrasing.instruction,
                                               answering: Conversation.instruction)
            try? FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: path
            )
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
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
