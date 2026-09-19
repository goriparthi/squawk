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
    private var castItems: [NSMenuItem] = []
    private let listener = SystemAudio()
    private let privacy = PrivacyWatch()
    let nowPlayingItem = NSMenuItem(title: "React to Audio", action: nil, keyEquivalent: "")
    let wellnessItem = NSMenuItem(title: "Look After Me", action: nil, keyEquivalent: "")
    /// When this run of work started, and what has been said about it.
    private var wellnessState = Wellness.State(startedAt: Date())
    private var wellnessUntil: Date?
    private var wellnessTimer: Timer?
    private var lastPrivacy = PrivacyState.clear
    private var wellnessPrompt: WellnessPrompt?
    private var fortuneUntil: Date?
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
            bubble.bottomAnchor.constraint(equalTo: ring.topAnchor),
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
            companion.topAnchor.constraint(equalTo: ring.topAnchor),
            companion.bottomAnchor.constraint(equalTo: background.bottomAnchor),

            face.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            face.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
            face.widthAnchor.constraint(equalTo: ring.widthAnchor, multiplier: 0.52),
            face.heightAnchor.constraint(equalTo: face.widthAnchor),
        ])

        // Two homes for the card: inside the head, or speaking above it.
        insideConstraints = [
            detail.centerXAnchor.constraint(equalTo: ring.centerXAnchor),
            detail.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
        ]
        bubbleConstraints = [
            detail.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
            detail.centerYAnchor.constraint(equalTo: bubble.centerYAnchor,
                                            constant: bubble.tailHeight / 2),
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
        listener.onSpectrum = { [weak self] spectrum in self?.companion.hear(spectrum) }
        startListeningIfWanted()
        // Always on. It opens nothing and needs no permission; it is the same
        // question the system's own dots answer, and a pet that shows it is
        // more use than one that does not.
        privacy.onChange = { [weak self] state in
            self?.companion.light(state)
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
        bubbleCentreConstraint?.constant = shift
        bubble.tailOffset = -diameter * 0.26 - shift
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
            ? BodyGeometry.bubbleHeight(head: diameter)
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
            let app = track?.source ?? NowPlaying.playingApplication()
            var lines: [String] = []
            if let bpm = companion.heardTempo { lines.append("\(bpm) bpm") }
            if let app { lines.append(app) }
            // A track name when a player will give one, the application that is
            // making the sound when it will not, and only then a shrug.
            detail.showNowPlaying(title: track?.title ?? app,
                                  artist: track?.artist,
                                  detail: lines.joined(separator: "  ·  "),
                                  artwork: track?.artwork)
            applyCardWidth()
            keepBubbleOnScreen()
            fortuneUntil = Date().addingTimeInterval(Self.fortuneLifetime)
            show()
            updateFace()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fortuneLifetime + 0.1) {
                [weak self] in
                guard let self, let until = fortuneUntil, Date() >= until else { return }
                fortuneUntil = nil
                render()
            }
            return
        }

        let text = Fortune.next(after: lastFortune)
        lastFortune = text
        detail.speak(text)
        applyCardWidth()
        fortuneUntil = Date().addingTimeInterval(Self.fortuneLifetime)
        show()
        updateFace()
        // Clearing it is a render like any other; the deadline decides.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fortuneLifetime + 0.1) { [weak self] in
            guard let self, let until = fortuneUntil, Date() >= until else { return }
            fortuneUntil = nil
            render()
        }
    }

    /// Double tapped its tummy, which starts the routine, and again to stop it.
    private func startDancing() {
        lastInteractionAt = Date()
        restlessUntil = nil
        fortuneUntil = nil
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
        if face == .dizzy, Settings.petStyle == .full, roster.isEmpty {
            wellnessUntil = nil
            detail.speak("NO")
            applyCardWidth()
            keepBubbleOnScreen()
            fortuneUntil = now.addingTimeInterval(Self.refusalLifetime)
            show()
            updateFace()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.refusalLifetime + 0.1) {
                [weak self] in
                guard let self, let until = fortuneUntil, Date() >= until else { return }
                fortuneUntil = nil
                render()
            }
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

    private func updateFace() {
        let awaiting = roster.entries.contains { $0.request.awaitsDecision }
        // Risk is judged on what you are actually being shown, not on the worst
        // thing in the queue, so the face matches the command under your eyes.
        let selected = ring.selectedID.flatMap { roster.entry(id: $0) }?.request
        let risky = selected.map {
            $0.awaitsDecision && RiskSignal.isRisky(tool: $0.tool, summary: $0.summary)
        } ?? false
        // The nudge outranks the resting face, but never anything waiting.
        if roster.isEmpty, let until = restlessUntil {
            if Date() < until {
                face.expression = .restless
                    companion.pose = BodyPose.pose(for: .restless)
                face.isHidden = Settings.petStyle == .full
                detail.isHidden = true
                bubble.isHidden = true
                return
            }
            restlessUntil = nil
        }

        // Looking after you holds the bubble, wearing the face that goes with
        // whatever it is asking: the stretch stretches, the eye break looks
        // away, and the late one is already half asleep.
        if let until = wellnessUntil, Date() < until, let prompt = wellnessPrompt {
            face.expression = prompt.face
            companion.grooves = false
            companion.pose = BodyPose.pose(for: prompt.face)
            face.isHidden = Settings.petStyle == .full
            detail.isHidden = false
            bubble.isHidden = Settings.petStyle != .full
            return
        }

        // A fortune holds the bubble, and the face stays pleased about it.
        if let until = fortuneUntil, Date() < until, roster.isEmpty {
            let refusing = lastPokeFace == .dizzy
                && Date().timeIntervalSince(lastPokeAt) < Self.refusalLifetime
            face.expression = refusing ? .dizzy : .happy
            // A refusal is aimed at you, and a sway laid over it aims it
            // somewhere else. Everything it says with its body holds still.
            companion.grooves = !refusing
            companion.pose = BodyPose.pose(for: refusing ? .dizzy : .happy)
            face.isHidden = Settings.petStyle == .full
            detail.isHidden = false
            bubble.isHidden = Settings.petStyle != .full
            return
        }
        fortuneUntil = nil

        // Music with nothing waiting is the one state worth being pleased about
        // on its own. Anything waiting still outranks it.
        if roster.isEmpty, companion.isHearingMusic, lastFaceEvent == nil,
           Settings.petStyle == .full {
            // Listening is not being ignored. The idle clock used to keep
            // running through a whole album, so the moment the music stopped it
            // reported an hour of neglect and the eyes fell shut.
            idleSince = Date()
            face.expression = .grooving
            companion.grooves = true
            companion.pose = BodyPose.pose(for: .grooving)
            face.isHidden = true
            detail.isHidden = true
            bubble.isHidden = true
            return
        }

        let expression = FaceMood.expression(
            waiting: roster.count,
            awaitingDecision: awaiting,
            lastEvent: lastFaceEvent,
            eventAge: Date().timeIntervalSince(lastFaceEventAt),
            idleFor: Date().timeIntervalSince(idleSince),
            risky: risky
        )
        face.expression = expression

        // With a body the card speaks from the bubble, so the face is free to
        // keep emoting while something is waiting. Without one they share the
        // middle, and anything waiting on you outranks the face.
        let showFace = Settings.petStyle == .full || roster.isEmpty
        // In the full style the model paints the face onto its own screen, so
        // the flat one is never drawn; it is still what decides the expression.
        face.isHidden = Settings.petStyle == .full || !showFace
        companion.pose = BodyPose.pose(for: expression)
        detail.isHidden = ring.selectedID == nil
            || (Settings.petStyle != .full && showFace)
        bubble.isHidden = Settings.petStyle != .full || detail.isHidden

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
            self?.companion.hear(spectrum)
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
            wellnessUntil = nil
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
        if let until = wellnessUntil, Date() >= until {
            wellnessUntil = nil
            render()
        }
        guard wellnessUntil == nil, fortuneUntil == nil, !companion.isDancing else { return }
        wellnessState.busy = !roster.isEmpty
        guard let prompt = Wellness.due(wellnessState) else { return }

        wellnessState.lastShown[prompt] = Date()
        wellnessState.lastAny = Date()
        wellnessUntil = Date().addingTimeInterval(prompt.lifetime)
        wellnessPrompt = prompt
        detail.speak(prompt.message)
        applyCardWidth()
        keepBubbleOnScreen()
        companion.quicken(for: prompt.lifetime)
        show()
        updateFace()
        DispatchQueue.main.asyncAfter(deadline: .now() + prompt.lifetime + 0.2) { [weak self] in
            guard let self, let until = wellnessUntil, Date() >= until else { return }
            wellnessUntil = nil
            wellnessPrompt = nil
            render()
        }
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
        listener.stop()
        privacy.stop()
        wellnessTimer?.invalidate()
        NSApp.terminate(nil)
    }
}
