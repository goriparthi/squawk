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
        let body = NSRect(x: bounds.minX, y: pointsUp ? bounds.minY : bounds.minY + tail,
                          width: bounds.width, height: bounds.height - tail)
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
