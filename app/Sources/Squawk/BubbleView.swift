import AppKit
import SquawkCore

/// A speech bubble above the head, for when the companion has a body. The card
/// inside the circle covers the eyes, which is the one thing the full style
/// exists to show, so in that style it speaks instead.
final class BubbleView: NSView {
    private let tail: CGFloat = 11

    /// Room the tail needs below the bubble body, so contents can be inset past it.
    var tailHeight: CGFloat { tail }

    /// Whether the tail points up rather than down: the bubble is under the
    /// pet, because the pet is parked near the top of the screen and there is
    /// no room above it.
    var pointsUp = false {
        didSet { needsDisplay = true }
    }

    /// How many cards are behind this one. The ring's arcs said "three waiting,
    /// this is the one you are reading" in a glance; with the ring hidden the
    /// modelled style said nothing at all, and this says it in the space the
    /// bubble already takes.
    var stackDepth = 0 {
        didSet {
            guard stackDepth != oldValue else { return }
            needsDisplay = true
        }
    }

    /// What the next one along is: amber for a decision, blue for a question,
    /// which is the rule the arcs used.
    var stackTint: NSColor = Palette.waiting {
        didSet { needsDisplay = true }
    }

    /// Stepping through the stack by hand.
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?

    /// Room the peeks take, which the height constraint has to allow for.
    var headroom: CGFloat { CardStack.headroom(waiting: stackDepth + 1) }

    /// How far the tail sits from the bubble's centre. Dead centre put it on the
    /// pet's face; off to one side it points at the head the way a speech
    /// bubble does. Clamped so it can never leave the bubble's rounded edge.
    var tailOffset: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    private func tailCentre(in body: NSRect) -> CGFloat {
        let room = max(0, body.width / 2 - 14 - tail)
        return bounds.midX + min(max(tailOffset, -room), room)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.height > tail * 2 else { return }
        // The peeks sit on the side away from the tail, so they never come
        // between the bubble and the head it is pointing at.
        let room = headroom
        let body = NSRect(x: bounds.minX,
                          y: bounds.minY + (pointsUp ? room : tail),
                          width: bounds.width, height: bounds.height - tail - room)
        drawStack(behind: body)
        let path = NSBezierPath(roundedRect: body, xRadius: 14, yRadius: 14)

        // The tail points at the head, which is what makes it speech rather
        // than a label that happens to be nearby. Down when the bubble is
        // above the pet, up when the pet is against the top of the screen and
        // the bubble has had to go underneath.
        let notch = NSBezierPath()
        let centre = tailCentre(in: body)
        if pointsUp {
            notch.move(to: NSPoint(x: centre - tail, y: body.maxY - 1))
            notch.line(to: NSPoint(x: centre + 2, y: bounds.maxY))
            notch.line(to: NSPoint(x: centre + tail, y: body.maxY - 1))
        } else {
            notch.move(to: NSPoint(x: centre - tail, y: body.minY + 1))
            notch.line(to: NSPoint(x: centre + 2, y: bounds.minY))
            notch.line(to: NSPoint(x: centre + tail, y: body.minY + 1))
        }
        notch.close()
        path.append(notch)

        NSGradient(colors: [Palette.faceTop, Palette.faceBottom])?.draw(in: path, angle: -90)
        Palette.rim.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    /// The cards behind this one, drawn before it so they are behind it.
    /// Fading back rather than out: one you cannot see is not saying there is
    /// anything there.
    private func drawStack(behind body: NSRect) {
        guard stackDepth > 0 else { return }
        for index in (0..<min(stackDepth, CardStack.drawnDepth)).reversed() {
            let rise = CardStack.offset(behind: index) * (pointsUp ? -1 : 1)
            let rect = body
                .insetBy(dx: CardStack.inset(behind: index), dy: 0)
                .offsetBy(dx: 0, dy: rise)
            let peek = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
            stackTint.withAlphaComponent(CardStack.alpha(behind: index)).setFill()
            peek.fill()
        }
    }

    /// The band the peeks occupy, which is where a click means "show me the
    /// next one" rather than "drag the pet somewhere".
    private func isOnAPeek(_ local: NSPoint) -> Bool {
        guard stackDepth > 0 else { return false }
        let room = headroom
        return pointsUp
            ? local.y <= bounds.minY + room
            : local.y >= bounds.maxY - room
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        guard isOnAPeek(local) else { return super.mouseDown(with: event) }
        onNext?()
    }

    /// Scrolling anywhere on the bubble cycles, because a five point strip is
    /// a poor target and this is the gesture people already try.
    override func scrollWheel(with event: NSEvent) {
        guard stackDepth > 0 else { return super.scrollWheel(with: event) }
        let step = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
            ? event.scrollingDeltaY : event.scrollingDeltaX
        guard abs(step) > 1 else { return }
        // Enough apart that one flick is one card rather than a blur.
        let now = event.timestamp
        guard now - lastScrollAt > 0.25 else { return }
        lastScrollAt = now
        step > 0 ? onPrevious?() : onNext?()
    }

    private var lastScrollAt: TimeInterval = 0

    /// Only the bubble itself takes clicks; the gap beside it belongs to
    /// whatever is behind the window.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if pointsUp {
            guard local.y <= bounds.maxY - tail else { return nil }
        } else {
            guard local.y >= bounds.minY + tail else { return nil }
        }
        return super.hitTest(point)
    }

    /// Where the tail points, in this view's own coordinates, so the layout can
    /// aim it at the head rather than assuming the middle.
    var tailTip: NSPoint {
        let body = NSRect(x: bounds.minX, y: pointsUp ? bounds.minY : bounds.minY + tail,
                          width: bounds.width, height: max(0, bounds.height - tail))
        return NSPoint(x: tailCentre(in: body), y: pointsUp ? bounds.maxY : bounds.minY)
    }
}
