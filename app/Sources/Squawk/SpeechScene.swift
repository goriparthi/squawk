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
        PendingRequest(id: "a", sessionId: "s", cwd: "/Users/me/agentbowl",
                       tool: "Agent", summary: "is waiting for your answer",
                       needsDecision: false),
        PendingRequest(id: "b", sessionId: "s", cwd: "/Users/me/squawk",
                       tool: "Bash", summary: "git push origin main --force-with-lease",
                       needsDecision: true),
    ]

    static func build(head: CGFloat, request: PendingRequest) -> Built {
        let canvas = BodyGeometry.canvas(head: head)
        let root = NSView(frame: NSRect(origin: .zero, size: canvas))
        let background = CircleBackgroundView(frame: root.bounds)
        background.showsBody = true
        background.headDiameter = head
        background.autoresizingMask = [.width, .height]
        root.addSubview(background)

        let bubble = BubbleView()
        let card = DetailView()
        card.tier = DialGeometry.tier(head, for: .full)
        let eyes = FaceView()
        eyes.expression = request.awaitsDecision ? .urgent : .curious
        for view in [bubble, card, eyes] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(view)
        }
        card.show(Roster.Entry(request: request, arrivedAt: Date()), waiting: 2)

        NSLayoutConstraint.activate([
            bubble.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            bubble.topAnchor.constraint(equalTo: background.topAnchor),
            bubble.heightAnchor.constraint(equalToConstant: BodyGeometry.bubbleHeight(head: head)),
            bubble.widthAnchor.constraint(equalToConstant: DialGeometry.bubbleWidth()),
            card.widthAnchor.constraint(equalToConstant: DialGeometry.cardWidth(head, for: .full)),
            card.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: bubble.centerYAnchor,
                                          constant: bubble.tailHeight / 2),
            eyes.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            eyes.centerYAnchor.constraint(equalTo: background.topAnchor,
                                          constant: BodyGeometry.bubbleHeight(head: head) + head / 2),
            eyes.widthAnchor.constraint(equalToConstant: head * 0.52),
            eyes.heightAnchor.constraint(equalTo: eyes.widthAnchor),
        ])
        root.layoutSubtreeIfNeeded()
        return Built(root: root, background: background, card: card)
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
