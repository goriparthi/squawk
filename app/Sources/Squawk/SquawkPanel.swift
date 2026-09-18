import AppKit
import SquawkCore

/// The floating dial. A non-activating panel so answering it never takes focus
/// from Slack or the browser you were actually reading.
final class SquawkPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        becomesKeyOnlyIfNeeded = true
        // Tracking areas that ask for .mouseMoved get nothing unless the window
        // opts in, which is what kept the hover card from ever appearing.
        acceptsMouseMovedEvents = true
    }

    // Borderless panels refuse key status by default, which would leave the
    // keyboard shortcuts dead.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The window is rectangular; only the companion is painted. macOS routes mouse
/// events by the window's alpha, so the untouched corners genuinely click
/// through to whatever is behind rather than swallowing the click.
final class CircleBackgroundView: NSView {
    /// When set, a body and arms are drawn behind the head, and the head moves
    /// to the top of the canvas to make room.
    var showsBody = false {
        didSet {
            guard showsBody != oldValue else { return }
            showsBody ? startSwinging() : stopSwinging()
            needsDisplay = true
        }
    }

    private var link: CADisplayLink?
    private var started = CACurrentMediaTime()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopSwinging() } else if showsBody { startSwinging() }
    }

    /// Arms are never perfectly still. A body that only moves when something
    /// happens reads as a picture of a robot rather than one.
    private func startSwinging() {
        guard link == nil, window != nil else { return }
        started = CACurrentMediaTime()
        let link = displayLink(target: self, selector: #selector(swingTick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopSwinging() {
        link?.invalidate()
        link = nil
    }

    @objc private func swingTick(_ sender: CADisplayLink) {
        swing = CGFloat(sin((CACurrentMediaTime() - started) * 1.6))
    }

    /// Where the arms are. Interpolated by the owner, never set per frame here.
    var pose = BodyPose.pose(for: .calm) {
        didSet { needsDisplay = true }
    }

    /// Radians of idle swing, so the arms are never perfectly still.
    var swing: CGFloat = 0 {
        didSet { if showsBody { needsDisplay = true } }
    }

    /// Set by the owner, because the canvas has a floor width and cannot be
    /// divided back into a head reliably.
    var headDiameter: CGFloat = 360

    /// The head's circle within this view. Everything functional is laid out
    /// against this rather than the whole canvas.
    var headFrame: NSRect {
        guard showsBody else {
            let diameter = min(bounds.width, bounds.height) - 2
            return NSRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2,
                          width: diameter, height: diameter)
        }
        // Below the bubble, which owns the top of the canvas.
        let head = headDiameter
        let bubble = BodyGeometry.bubbleHeight(head: head)
        return NSRect(x: bounds.midX - head / 2,
                      y: bounds.maxY - bubble - head,
                      width: head, height: head)
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = headFrame
        if showsBody { drawBody(head: circle) }
        let path = NSBezierPath(ovalIn: circle)

        // Not the panel colour: at #0C1317 the face was near black and vanished
        // against a dark desktop, so you could not tell dial from background.
        // A lit instrument face instead, lighter at the top, with a rim.
        NSGradient(colors: [Palette.faceTop, Palette.faceBottom])?
            .draw(in: path, angle: -90)

        Palette.rim.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        // A hairline just inside the rim, which is what reads as a bezel rather
        // than a flat disc.
        let inner = NSBezierPath(ovalIn: circle.insetBy(dx: 2.5, dy: 2.5))
        Palette.innerRim.setStroke()
        inner.lineWidth = 1
        inner.stroke()
    }

    /// Outside the painted shape the window is transparent, so the click belongs
    /// to the app underneath. Without this the rectangular frame would eat it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let head = headFrame
        let radius = head.width / 2
        let dx = local.x - head.midX
        let dy = local.y - head.midY
        if dx * dx + dy * dy <= radius * radius { return super.hitTest(point) }
        guard showsBody, bodyPath(head: head).contains(local) else { return nil }
        return super.hitTest(point)
    }

    /// An egg drawn as two mirrored curves: narrow at the shoulders, widest low
    /// down, which is the whole silhouette of this kind of companion.
    private func bodyPath(head: NSRect) -> NSBezierPath {
        let size = BodyGeometry.bodySize(head: head.width)
        let top = head.midY - BodyGeometry.bodyTop(head: head.width)
        let bottom = top - size.height
        let centre = bounds.midX
        let halfWide = size.width / 2
        let halfNarrow = halfWide * BodyGeometry.shoulderTaper
        let widest = bottom + size.height * 0.34

        let path = NSBezierPath()
        path.move(to: NSPoint(x: centre, y: top))
        path.curve(to: NSPoint(x: centre + halfWide, y: widest),
                   controlPoint1: NSPoint(x: centre + halfNarrow, y: top),
                   controlPoint2: NSPoint(x: centre + halfWide, y: top - size.height * 0.30))
        path.curve(to: NSPoint(x: centre, y: bottom),
                   controlPoint1: NSPoint(x: centre + halfWide, y: bottom - size.height * 0.20),
                   controlPoint2: NSPoint(x: centre + halfWide * 0.52, y: bottom))
        path.curve(to: NSPoint(x: centre - halfWide, y: widest),
                   controlPoint1: NSPoint(x: centre - halfWide * 0.52, y: bottom),
                   controlPoint2: NSPoint(x: centre - halfWide, y: bottom - size.height * 0.20))
        path.curve(to: NSPoint(x: centre, y: top),
                   controlPoint1: NSPoint(x: centre - halfWide, y: top - size.height * 0.30),
                   controlPoint2: NSPoint(x: centre - halfNarrow, y: top))
        path.close()
        return path
    }

    /// A tapered paddle rather than a stick with a ball on the end.
    private func armPath(root: NSPoint, upper: NSPoint, hand: NSPoint, width: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: root)
        path.curve(to: hand,
                   controlPoint1: NSPoint(x: upper.x, y: upper.y),
                   controlPoint2: NSPoint(x: upper.x, y: upper.y))
        let flat = path.copy() as! NSBezierPath
        flat.lineWidth = width * 0.62
        flat.lineCapStyle = .round
        flat.lineJoinStyle = .round
        return flat
    }

    /// Arms first, so they sit behind the body, then the body over their roots.
    private func drawBody(head: NSRect) {
        let length = BodyGeometry.armLength(head: head.width)
        let width = BodyGeometry.armWidth(head: head.width)
        let body = bodyPath(head: head).bounds

        for side in [-1.0, 1.0] as [CGFloat] {
            let arm = side < 0 ? pose.left : pose.right
            let root = NSPoint(x: side < 0 ? body.minX + width * 0.3 : body.maxX - width * 0.3,
                               y: body.maxY - body.height * 0.22)
            // Idle swing rides on top of the pose, scaled by how lively it is.
            let idle = Double(swing) * pose.liveliness * 6 * (side < 0 ? 1 : -1)
            let shoulder = (arm.shoulder + idle) * .pi / 180
            let elbow = arm.elbow * .pi / 180

            let upper = NSPoint(
                x: root.x + side * CGFloat(sin(shoulder)) * length * 0.58,
                y: root.y - CGFloat(cos(shoulder)) * length * 0.58
            )
            let hand = NSPoint(
                x: upper.x + side * CGFloat(sin(shoulder + elbow)) * length * 0.52,
                y: upper.y - CGFloat(cos(shoulder + elbow)) * length * 0.52
            )

            // Thin at the shoulder, broad at the hand: a paddle, which reads as
            // a limb where an even stroke reads as a wire.
            Palette.line.setStroke()
            let limb = armPath(root: root, upper: upper, hand: hand, width: width)
            limb.stroke()

            Palette.faceTop.setFill()
            let paddle = NSBezierPath(ovalIn: NSRect(
                x: hand.x - width * 0.56, y: hand.y - width * 0.72,
                width: width * 1.12, height: width * 1.44
            ))
            let tilt = NSAffineTransform()
            tilt.translateX(by: hand.x, yBy: hand.y)
            tilt.rotate(byDegrees: side < 0 ? arm.shoulder * 0.6 : -arm.shoulder * 0.6)
            tilt.translateX(by: -hand.x, yBy: -hand.y)
            paddle.transform(using: tilt as AffineTransform)
            paddle.fill()
        }

        // The stand, drawn before the body so the body sits on it.
        let base = BodyGeometry.baseSize(head: head.width)
        Palette.line.withAlphaComponent(0.55).setFill()
        NSBezierPath(ovalIn: NSRect(
            x: bounds.midX - base.width / 2, y: bounds.minY + 2,
            width: base.width, height: base.height
        )).fill()

        let shell = bodyPath(head: head)
        NSGradient(colors: [Palette.faceTop, Palette.faceBottom])?.draw(in: shell, angle: -90)
        Palette.rim.setStroke()
        shell.lineWidth = 1.5
        shell.stroke()
    }
}

/// Buttons in a non-activating panel are clicked while another app owns focus,
/// so each one has to opt into acting on the first press.
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
