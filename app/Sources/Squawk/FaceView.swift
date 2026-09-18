import AppKit
import SquawkCore

/// The dial's face. Driven by a display link rather than discrete property
/// changes: every value is interpolated, so expressions morph instead of
/// snapping, which is the difference between a companion and a status light.
final class FaceView: NSView {
    var expression: FaceExpression = .calm {
        didSet {
            guard expression != oldValue else { return }
            goal = FaceFrame.target(for: expression)
            wake()
        }
    }

    private var frameState = FaceFrame()
    private var goal = FaceFrame()
    private var link: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    private var blinkStartedAt: CFTimeInterval = -1
    private var nextBlinkAt: CFTimeInterval = 0
    /// Where the eyes are looking, as a share of the eye width. Drifts, so the
    /// face is never perfectly still.
    private var gaze = CGPoint.zero
    private var gazeGoal = CGPoint.zero
    private var nextGazeAt: CFTimeInterval = 0
    private var clock: CFTimeInterval = 0

    override var isFlipped: Bool { false }
    /// The face is drawn over the dial; clicks belong to what is beneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window == nil ? stop() : start()
    }

    private func start() {
        guard link == nil else { return }
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTick = CACurrentMediaTime()
        nextBlinkAt = lastTick + Double.random(in: 2.4...6.0)
        nextGazeAt = lastTick + Double.random(in: 1.6...4.0)
    }

    private func stop() {
        link?.invalidate()
        link = nil
    }

    /// Restarts the clock after an idle stop, so a change is never waiting on
    /// the next scheduled wake.
    /// Jumps straight to the target. An offscreen render has no display link to
    /// interpolate it, and a contact sheet wants the settled face anyway.
    func settle() {
        frameState = goal
        needsDisplay = true
    }

    private func wake() {
        if link == nil, window != nil { start() }
        needsDisplay = true
    }

    @objc private func tick(_ sender: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 1.0 / 20)
        lastTick = now
        clock = now

        frameState = FaceFrame.approach(frameState, toward: goal, dt: dt)

        if now >= nextBlinkAt, blinkStartedAt < 0 {
            blinkStartedAt = now
        }
        if blinkStartedAt >= 0, now - blinkStartedAt > Blink.duration {
            blinkStartedAt = -1
            // Never a metronome; an even rhythm reads as a machine ticking.
            nextBlinkAt = now + Double.random(in: 2.4...6.4)
        }

        if now >= nextGazeAt {
            gazeGoal = CGPoint(x: .random(in: -0.16...0.16), y: .random(in: -0.08...0.08))
            nextGazeAt = now + Double.random(in: 1.6...4.2)
        }
        let g = 1 - pow(2, -dt / 0.22)
        gaze.x += (gazeGoal.x - gaze.x) * g
        gaze.y += (gazeGoal.y - gaze.y) * g

        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let span = min(bounds.width, bounds.height)
        guard span > 20 else { return }

        let blink = blinkStartedAt < 0 ? 1 : Blink.openness(at: clock - blinkStartedAt)
        let eyeW = span * 0.32
        let eyeH = max(span * 0.27 * frameState.openness * blink, span * 0.018)
        let gap = span * 0.15
        // A slow breath, so the face is alive even when nothing is happening.
        let breath = sin(clock * 0.9) * span * 0.006
        let centre = CGPoint(
            x: bounds.midX + gaze.x * span * 0.05,
            y: bounds.midY + span * 0.05 + gaze.y * span * 0.03 + breath
        )

        let glow = NSShadow()
        glow.shadowColor = Palette.brand.withAlphaComponent(0.6)
        glow.shadowBlurRadius = span * 0.055
        glow.shadowOffset = .zero

        NSGraphicsContext.saveGraphicsState()
        glow.set()
        Palette.brand.setFill()
        Palette.brand.setStroke()

        for side in [-1.0, 1.0] as [CGFloat] {
            let lift = span * frameState.headTilt * (side < 0 ? 1 : -1) * 0.35
            let frame = NSRect(
                x: side < 0 ? centre.x - gap / 2 - eyeW : centre.x + gap / 2,
                y: centre.y - eyeH / 2 + lift,
                width: eyeW, height: eyeH
            )
            // Shut is continuous, so an eye folds into an arc rather than cutting.
            let shut = max(frameState.squint, side < 0 ? frameState.winkLeft : 0)
            drawEye(in: frame, side: side, shut: shut, span: span)
            if frameState.brows > 0.01 {
                drawBrow(over: frame, span: span, alpha: frameState.brows)
            }
        }

        if abs(frameState.mouth) > 0.01 {
            drawMouth(centre: centre, span: span)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawEye(in frame: NSRect, side: CGFloat, shut: Double, span: CGFloat) {
        if shut < 0.995 {
            NSGraphicsContext.saveGraphicsState()
            if shut > 0.01 {
                Palette.brand.withAlphaComponent(1 - shut).setFill()
            }
            let tilt = CGFloat(frameState.tilt) * (side < 0 ? 1 : -1)
            if tilt != 0 {
                let spin = NSAffineTransform()
                spin.translateX(by: frame.midX, yBy: frame.midY)
                spin.rotate(byDegrees: tilt)
                spin.translateX(by: -frame.midX, yBy: -frame.midY)
                spin.concat()
            }
            // The eye closes by squashing toward its own centre, not by fading.
            let squashed = frame.insetBy(dx: 0, dy: frame.height * CGFloat(shut) * 0.5)
            // Soft to the point of being a squircle, which is what stops a wide
            // eye reading as a bar.
            let radius = min(squashed.width, squashed.height) * 0.48
            NSBezierPath(roundedRect: squashed, xRadius: radius, yRadius: radius).fill()

            NSGraphicsContext.restoreGraphicsState()
        }

        guard shut > 0.005 else { return }
        Palette.brand.withAlphaComponent(shut).setStroke()
        let arc = NSBezierPath()
        arc.lineWidth = max(2, span * 0.042)
        arc.lineCapStyle = .round
        let radius = frame.width * 0.60
        let origin = NSPoint(x: frame.midX, y: frame.midY - radius * 0.30)
        arc.appendArc(withCenter: origin, radius: radius, startAngle: 25, endAngle: 155)
        arc.stroke()
        Palette.brand.setStroke()
    }

    private func drawBrow(over frame: NSRect, span: CGFloat, alpha: Double) {
        Palette.brand.withAlphaComponent(alpha).setStroke()
        let brow = NSBezierPath()
        brow.lineWidth = max(2, span * 0.034)
        brow.lineCapStyle = .round
        let radius = frame.width * 0.62
        let centre = NSPoint(x: frame.midX, y: frame.maxY + span * 0.02)
        brow.appendArc(withCenter: centre, radius: radius, startAngle: 40, endAngle: 140)
        brow.stroke()
        Palette.brand.setStroke()
    }

    private func drawMouth(centre: CGPoint, span: CGFloat) {
        // Clear of the eyes even when one is lowered by a head tilt.
        let y = centre.y - span * 0.34
        let triangle = CGFloat(frameState.triangle)

        if triangle > 0.01 {
            Palette.brand.withAlphaComponent(Double(triangle)).setFill()
            let width = span * 0.16 * triangle
            let height = span * 0.11 * triangle
            let mouth = NSBezierPath()
            mouth.move(to: NSPoint(x: centre.x - width / 2, y: y + height / 2))
            mouth.line(to: NSPoint(x: centre.x + width / 2, y: y + height / 2))
            mouth.line(to: NSPoint(x: centre.x, y: y - height / 2))
            mouth.close()
            mouth.fill()
            Palette.brand.setFill()
        }

        guard triangle < 0.99 else { return }
        Palette.brand.withAlphaComponent(Double(1 - triangle)).setStroke()
        let curve = CGFloat(frameState.mouth)
        let width = span * 0.28
        let path = NSBezierPath()
        path.lineWidth = max(2, span * 0.038)
        path.lineCapStyle = .round
        path.move(to: NSPoint(x: centre.x - width / 2, y: y))
        path.curve(
            to: NSPoint(x: centre.x + width / 2, y: y),
            controlPoint1: NSPoint(x: centre.x - width / 4, y: y - curve * span * 0.13),
            controlPoint2: NSPoint(x: centre.x + width / 4, y: y - curve * span * 0.13)
        )
        path.stroke()
        Palette.brand.setStroke()
    }
}
