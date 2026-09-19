import AppKit
import SquawkCore

/// The companion with its speech bubble filled, built offscreen. Both the
/// preview sheet and the reachability check use it, so what is rendered and
/// what is hit tested are the same thing.
@MainActor
enum SpeechScene {
    struct Built {
        let root: NSView
        let background: CircleBackgroundView
        let card: DetailView
    }

    static let heads: [CGFloat] = [50, 120, 300]

    static let samples = [
        PendingRequest(id: "a", sessionId: "s", cwd: "/Users/me/i3logix",
                       tool: "idle_prompt", summary: "Claude is waiting for your input",
                       needsDecision: false),
        PendingRequest(id: "b", sessionId: "s", cwd: "/Users/me/squawk",
                       tool: "Bash", summary: "git push origin main --force-with-lease",
                       needsDecision: true),
    ]

    static func build(head: CGFloat, request: PendingRequest, fortune: String? = nil) -> Built {
        let canvas = BodyGeometry.canvas(head: head)
        let root = NSView(frame: NSRect(origin: .zero, size: canvas))
        let background = CircleBackgroundView(frame: root.bounds)
        background.isModelled = true
        background.autoresizingMask = [.width, .height]
        root.addSubview(background)

        let companion = CompanionView(face: FaceAnimator())
        companion.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(companion)

        let bubble = BubbleView()
        let card = DetailView()
        card.tier = DialGeometry.tier(head, for: .full)
        let eyes = FaceView()
        eyes.expression = request.awaitsDecision ? .urgent : .curious
        for view in [bubble, card, eyes] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        if let fortune {
            card.speak(fortune)
        } else {
            card.show(Roster.Entry(request: request, arrivedAt: Date()), waiting: 2)
        }
        bubble.tailOffset = -head * 0.26

        NSLayoutConstraint.activate([
            bubble.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            bubble.bottomAnchor.constraint(equalTo: background.topAnchor,
                                           constant: BodyGeometry.bubbleHeight(head: head)),
            bubble.widthAnchor.constraint(equalTo: card.widthAnchor,
                                          constant: 2 * DialGeometry.bubblePadding),
            bubble.heightAnchor.constraint(equalTo: card.heightAnchor,
                                           constant: 2 * DialGeometry.bubblePadding
                                               + bubble.tailHeight),
            card.widthAnchor.constraint(
                equalToConstant: card.fitWidth(within: DialGeometry.bubbleCardWidth)),
            card.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: bubble.centerYAnchor,
                                          constant: bubble.tailHeight / 2),
            companion.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            companion.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            companion.topAnchor.constraint(equalTo: background.topAnchor,
                                           constant: BodyGeometry.bubbleHeight(head: head)),
            companion.bottomAnchor.constraint(equalTo: background.bottomAnchor),

            eyes.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            eyes.centerYAnchor.constraint(equalTo: background.topAnchor,
                                          constant: BodyGeometry.bubbleHeight(head: head) + head / 2),
            eyes.widthAnchor.constraint(equalToConstant: head * 0.52),
            eyes.heightAnchor.constraint(equalTo: eyes.widthAnchor),
        ])
        root.layoutSubtreeIfNeeded()
        return Built(root: root, background: background, card: card)
    }

    /// Whether a click on the pet itself reaches the companion, which is what
    /// carries poking, rubbing and the double tap. The card's buttons having
    /// their own check says nothing about the pet underneath them.
    static func petIsReachable() -> String? {
        let scene = build(head: 300, request: samples[0])
        guard let companion = scene.background.subviews
            .compactMap({ $0 as? CompanionView }).first
        else { return "there is no companion view in the panel at all" }
        // The middle of the region the companion occupies, which is its body.
        let centre = NSPoint(x: companion.frame.midX, y: companion.frame.midY)
        guard let hit = scene.background.hitTest(centre) else {
            return "a click on the pet's body reaches nothing"
        }
        guard hit === companion || hit.isDescendant(of: companion) else {
            return "a click on the pet's body lands on \(type(of: hit))"
        }
        // The tummy is one part of the pet, not all of it: a double tap needs
        // somewhere it does not start a dance, and a poke somewhere it lands.
        let column = stride(from: companion.bounds.minY + 1, to: companion.bounds.maxY, by: 3)
            .map { NSPoint(x: companion.bounds.midX, y: $0) }
        let onPet = column.filter(companion.isOnThePet).count
        let tummy = column.filter(companion.isTummy).count
        guard tummy > 0 else { return "no point down the pet's middle is its tummy" }
        guard tummy < onPet else { return "every point down the pet's middle is its tummy" }
        return nil
    }

    /// Whether the pet reads clicks as it should: a tap on the head pokes, a
    /// tap on the tummy giggles, a double tap there dances, and a drag is nothing.
    /// Events go straight to the view: a non activating panel never sees events
    /// posted to the process, so this is the only place clicks can be checked.
    static func clicksAreUnderstood() -> String? {
        let scene = build(head: 300, request: samples[0])
        guard let companion = scene.background.subviews
            .compactMap({ $0 as? CompanionView }).first
        else { return "there is no companion view in the panel at all" }
        let column = stride(from: companion.bounds.maxY - 1, to: companion.bounds.minY, by: -3)
            .map { NSPoint(x: companion.bounds.midX, y: $0) }
        guard let head = column.first(where: { companion.isOnThePet($0) && !companion.isTummy($0) }),
              let tummy = column.first(where: companion.isTummy)
        else { return "could not find both a head and a tummy down the pet's middle" }

        var pokes = 0
        var dances = 0
        var giggles = 0
        companion.onPoke = { pokes += 1 }
        companion.onTummyDoubleClick = { dances += 1 }
        companion.onGiggle = { giggles += 1 }
        func click(_ point: NSPoint, count: Int, releasedAt release: NSPoint? = nil) {
            let clock = ProcessInfo.processInfo.systemUptime
            for (type, location) in [(NSEvent.EventType.leftMouseDown, point),
                                     (NSEvent.EventType.leftMouseUp, release ?? point)] {
                guard let event = NSEvent.mouseEvent(
                    with: type, location: companion.convert(location, to: nil), modifierFlags: [],
                    timestamp: clock, windowNumber: 0, context: nil, eventNumber: 0,
                    clickCount: count, pressure: 1)
                else { continue }
                type == .leftMouseDown ? companion.mouseDown(with: event) : companion.mouseUp(with: event)
            }
        }

        click(head, count: 1)
        guard pokes == 1, dances == 0 else { return "a tap on the head gave \(pokes) pokes, \(dances) dances" }
        for count in 1...4 { click(head, count: count) }
        guard pokes == 5, dances == 0 else { return "four quick taps on the head gave \(pokes) pokes, \(dances) dances" }
        click(tummy, count: 1)
        guard pokes == 5, dances == 0, giggles == 1 else { return "a tap on the tummy gave \(pokes) pokes, \(dances) dances, \(giggles) giggles" }
        click(tummy, count: 2)
        guard dances == 1, pokes == 5 else { return "a double tap on the tummy gave \(dances) dances, \(pokes) pokes" }
        click(tummy, count: 3)
        guard dances == 1 else { return "a third tap on the tummy danced again" }
        click(head, count: 1, releasedAt: NSPoint(x: head.x + 30, y: head.y))
        guard pokes == 5 else { return "dragging the pet counted as a poke" }
        return nil
    }

    /// Whether the pointer can actually reach every control that is showing. A
    /// button outside the background's hit region looks identical to a live one,
    /// which is how the whole bubble shipped unclickable.
    struct Unreachable {
        let head: CGFloat
        let control: String
        let landedOn: String
    }

    static func unreachableControls() -> [Unreachable] {
        var missed: [Unreachable] = []
        for head in heads {
            for request in samples {
                let scene = build(head: head, request: request)
                for control in scene.card.liveControls {
                    // hitTest takes a point in the receiver's superview space,
                    // and the background fills the root, so they are the same.
                    let centre = control.convert(
                        NSPoint(x: control.bounds.midX, y: control.bounds.midY), to: scene.root)
                    let hit = scene.background.hitTest(centre)
                    let reached = hit === control || hit?.isDescendant(of: control) == true
                    if !reached {
                        missed.append(Unreachable(
                            head: head,
                            control: (control as? NSButton)?.title ?? "\(type(of: control))",
                            landedOn: hit.map { "\(type(of: $0))" } ?? "nothing"
                        ))
                    }
                }
            }
        }
        return missed
    }
}
