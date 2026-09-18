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
        // Below the bubble, which owns the top of the canvas. A canvas with no
        // room for one (an offscreen render) simply has no bubble.
        let head = headDiameter
        let bubble = bounds.height - head > BodyGeometry.bubbleHeight(head: head) + head * 0.8
            ? BodyGeometry.bubbleHeight(head: head)
            : 0
        return NSRect(x: bounds.midX - head / 2,
                      y: bounds.maxY - bubble - head - head * 0.04,
                      width: head, height: head)
    }

    override func draw(_ dirtyRect: NSRect) {
        let circle = headFrame
        if showsBody {
            drawBody(head: circle)
            drawShell(around: circle)
        }
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

    /// The head shell: a squircle with ears, sitting behind the scope. Eilik is
    /// built the same way, a rounded square holding a dark oval screen.
    private func drawShell(around head: NSRect) {
        let size = BodyGeometry.shellSize(head: head.width)
        let rect = NSRect(x: head.midX - size.width / 2, y: head.midY - size.height / 2,
                          width: size.width, height: size.height)
        let corner = BodyGeometry.shellCorner(head: head.width)
        let ear = BodyGeometry.earSize(head: head.width)

        for side in [-1.0, 1.0] as [CGFloat] {
            let x = side < 0 ? rect.minX - ear.width * 0.55 : rect.maxX - ear.width * 0.45
            let bump = NSBezierPath(roundedRect: NSRect(
                x: x, y: rect.midY - ear.height / 2,
                width: ear.width, height: ear.height
            ), xRadius: ear.width / 2, yRadius: ear.width / 2)
            Palette.line.setFill()
            bump.fill()
        }

        let shell = NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner)
        NSGradient(colors: [Palette.shellTop, Palette.shellBottom])?.draw(in: shell, angle: -90)
        Palette.rim.setStroke()
        shell.lineWidth = 1.5
        shell.stroke()
        highlight(on: shell, in: rect, strength: 0.9)
    }

    /// A soft sheen across the upper left, which is what gives a flat fill
    /// volume. Clipped to the shape so it never leaks past the silhouette.
    private func highlight(on path: NSBezierPath, in rect: NSRect, strength: CGFloat) {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let sheen = NSBezierPath(ovalIn: NSRect(
            x: rect.minX - rect.width * 0.18,
            y: rect.midY - rect.height * 0.04,
            width: rect.width * 0.96,
            height: rect.height * 0.78
        ))
        NSGradient(colors: [
            Palette.shellHighlight.withAlphaComponent(0.34 * strength),
            Palette.shellHighlight.withAlphaComponent(0),
        ])?.draw(in: sheen, relativeCenterPosition: NSPoint(x: -0.25, y: 0.45))
        NSGraphicsContext.restoreGraphicsState()
    }

    /// A soft contact shadow, so it sits on the stand rather than floating.
    private func groundShadow(under rect: NSRect, head: CGFloat) {
        let size = BodyGeometry.baseSize(head: head)
        let shadow = NSBezierPath(ovalIn: NSRect(
            x: bounds.midX - size.width / 2, y: rect.minY - size.height * 0.35,
            width: size.width, height: size.height * 1.5
        ))
        NSGradient(colors: [
            NSColor.black.withAlphaComponent(0.42),
            NSColor.black.withAlphaComponent(0),
        ])?.draw(in: shadow, relativeCenterPosition: .zero)
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
        let widest = bottom + size.height * 0.40

        let path = NSBezierPath()
        path.move(to: NSPoint(x: centre, y: top))
        path.curve(to: NSPoint(x: centre + halfWide, y: widest),
                   controlPoint1: NSPoint(x: centre + halfNarrow, y: top),
                   controlPoint2: NSPoint(x: centre + halfWide, y: top - size.height * 0.30))
        path.curve(to: NSPoint(x: centre, y: bottom),
                   controlPoint1: NSPoint(x: centre + halfWide, y: bottom + size.height * 0.14),
                   controlPoint2: NSPoint(x: centre + halfWide * 0.66, y: bottom))
        path.curve(to: NSPoint(x: centre - halfWide, y: widest),
                   controlPoint1: NSPoint(x: centre - halfWide * 0.66, y: bottom),
                   controlPoint2: NSPoint(x: centre - halfWide, y: bottom + size.height * 0.14))
        path.curve(to: NSPoint(x: centre, y: top),
                   controlPoint1: NSPoint(x: centre - halfWide, y: top - size.height * 0.30),
                   controlPoint2: NSPoint(x: centre - halfNarrow, y: top))
        path.close()
        return path
    }

    /// A limb as one closed blade: narrow at the shoulder, widest two thirds
    /// along, rounded at the tip. Drawn as a shape rather than stroked, because
    /// a stroke of even width is a wire and a knob on the end is a lollipop.
    private func armPath(root: NSPoint, upper: NSPoint, hand: NSPoint, width: CGFloat) -> NSBezierPath {
        let dx = hand.x - root.x
        let dy = hand.y - root.y
        let length = max(hypot(dx, dy), 0.001)
        // Unit normal, which is the direction the blade has width in.
        let nx = -dy / length
        let ny = dx / length

        let rootHalf = width * 0.30
        let bellyHalf = width * 0.62
        let tipHalf = width * 0.44

        func offset(_ point: NSPoint, _ amount: CGFloat) -> NSPoint {
            NSPoint(x: point.x + nx * amount, y: point.y + ny * amount)
        }
        let belly = NSPoint(x: root.x + dx * 0.62 + (upper.x - root.x) * 0.18,
                            y: root.y + dy * 0.62 + (upper.y - root.y) * 0.18)

        let path = NSBezierPath()
        path.move(to: offset(root, rootHalf))
        path.curve(to: offset(hand, tipHalf),
                   controlPoint1: offset(belly, bellyHalf),
                   controlPoint2: offset(hand, tipHalf * 1.3))
        // Round the tip across, then back down the other edge.
        path.curve(to: offset(hand, -tipHalf),
                   controlPoint1: NSPoint(x: hand.x + (dx / length) * tipHalf * 1.5 + nx * tipHalf,
                                          y: hand.y + (dy / length) * tipHalf * 1.5 + ny * tipHalf),
                   controlPoint2: NSPoint(x: hand.x + (dx / length) * tipHalf * 1.5 - nx * tipHalf,
                                          y: hand.y + (dy / length) * tipHalf * 1.5 - ny * tipHalf))
        path.curve(to: offset(root, -rootHalf),
                   controlPoint1: offset(hand, -tipHalf * 1.3),
                   controlPoint2: offset(belly, -bellyHalf))
        path.close()
        return path
    }

    /// Arms first, so they sit behind the body, then the body over their roots.
    private func drawBody(head: NSRect) {
        let length = BodyGeometry.armLength(head: head.width)
        let width = BodyGeometry.armWidth(head: head.width)
        let body = bodyPath(head: head).bounds

        for side in [-1.0, 1.0] as [CGFloat] {
            let arm = side < 0 ? pose.left : pose.right
            // Built on the right, then mirrored for the left. Computing both
            // directly made a symmetric pose render lopsided.
            let root = NSPoint(x: body.maxX - width * 0.10,
                               y: body.maxY - body.height * 0.30)
            let idle = Double(swing) * pose.liveliness * 6 * (side < 0 ? 1 : -1)
            let shoulder = (arm.shoulder + idle) * .pi / 180
            let elbow = arm.elbow * .pi / 180

            let upper = NSPoint(
                x: root.x + CGFloat(sin(shoulder)) * length * 0.58,
                y: root.y - CGFloat(cos(shoulder)) * length * 0.58
            )
            let hand = NSPoint(
                x: upper.x + CGFloat(sin(shoulder + elbow)) * length * 0.52,
                y: upper.y - CGFloat(cos(shoulder + elbow)) * length * 0.52
            )

            let limb = armPath(root: root, upper: upper, hand: hand, width: width)
            if side < 0 {
                let mirror = NSAffineTransform()
                mirror.translateX(by: bounds.midX, yBy: 0)
                mirror.scaleX(by: -1, yBy: 1)
                mirror.translateX(by: -bounds.midX, yBy: 0)
                limb.transform(using: mirror as AffineTransform)
            }
            NSGradient(colors: [Palette.shellTop, Palette.shellBottom])?
                .draw(in: limb, angle: -90)
            Palette.rim.withAlphaComponent(0.8).setStroke()
            limb.lineWidth = 1
            limb.stroke()
        }

        let shell = bodyPath(head: head)
        groundShadow(under: shell.bounds, head: head.width)

        // The stand, drawn before the body so the body sits on it.
        let base = BodyGeometry.baseSize(head: head.width)
        let stand = NSBezierPath(ovalIn: NSRect(
            x: bounds.midX - base.width / 2, y: shell.bounds.minY - base.height * 0.45,
            width: base.width, height: base.height
        ))
        NSGradient(colors: [Palette.shellTop, Palette.shellBottom])?.draw(in: stand, angle: -90)

        NSGradient(colors: [Palette.shellTop, Palette.shellBottom])?.draw(in: shell, angle: -90)
        Palette.rim.setStroke()
        shell.lineWidth = 1.5
        shell.stroke()
        highlight(on: shell, in: shell.bounds, strength: 1.0)
    }
}

/// Buttons in a non-activating panel are clicked while another app owns focus,
/// so each one has to opt into acting on the first press.
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
