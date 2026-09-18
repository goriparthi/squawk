import AppKit
import SquawkCore

/// Draws a face into a rectangle. Pulled out of the view so the modelled
/// companion can paint the same face onto its screen: one artist, so the two
/// renderers cannot drift into two different creatures.
struct FaceArtist {
    /// Whether to draw the eyes' glow here. The flat dial does; the modelled
    /// companion does not, because its camera has a bloom pass that produces a
    /// better glow on the GPU for nothing. A 28 point CoreGraphics blur over
    /// the whole face, every frame, was three quarters of the model's CPU.
    var glows = true
    /// What is playing, when the pet is listening. Drawn under the eyes.
    var spectrum: Spectrum?
    var frame = FaceFrame()
    var gaze = CGPoint.zero
    var clock: CFTimeInterval = 0
    /// Negative when the eyes are open.
    var blinkStartedAt: CFTimeInterval = -1

    /// Stands in for "would this draw any differently?". Repainting a face that
    /// has not changed was costing three quarters of the companion's frame
    /// time, all of it redrawing the same eyes and handing the same megabyte to
    /// the GPU. Quantised, because a change too small to move a pixel is not a
    /// change.
    var signature: Int {
        var hasher = Hasher()
        for value in [frame.openness, frame.squint, frame.winkLeft, frame.brows,
                      frame.mouth, frame.triangle, frame.crossedOut, frame.tilt,
                      frame.headTilt, frame.gazeBias, frame.red, frame.green, frame.blue] {
            hasher.combine(Int((value * 400).rounded()))
        }
        hasher.combine(Int((gaze.x * 400).rounded()))
        hasher.combine(Int((gaze.y * 400).rounded()))
        // The breath and the blink are the only things the clock feeds.
        hasher.combine(Int((sin(clock * 0.9) * 400).rounded()))
        hasher.combine(blinkStartedAt < 0 ? 0 : Int(((clock - blinkStartedAt) * 240).rounded()))
        for band in spectrum?.bands ?? [] { hasher.combine(Int((band * 90).rounded())) }
        return hasher.finalize()
    }

    /// The interpolated mood colour, so a hue washes in with the shape rather
    /// than switching under it.
    var eyeColour: NSColor {
        NSColor(srgbRed: CGFloat(frame.red), green: CGFloat(frame.green),
                blue: CGFloat(frame.blue), alpha: 1)
    }


    func draw(in bounds: NSRect) {
        let span = min(bounds.width, bounds.height)
        guard span > 20 else { return }

        let blink = blinkStartedAt < 0 ? 1 : Blink.openness(at: clock - blinkStartedAt)
        let eyeW = span * 0.355
        let eyeH = max(span * 0.27 * frame.openness * blink, span * 0.018)
        let gap = span * 0.185
        // A slow breath, so the face is alive even when nothing is happening.
        let breath = sin(clock * 0.9) * span * 0.006
        let centre = CGPoint(
            x: bounds.midX + (gaze.x + frame.gazeBias * 0.4) * span * 0.05,
            y: bounds.midY + span * 0.05 + gaze.y * span * 0.03 + breath
        )

        NSGraphicsContext.saveGraphicsState()
        if glows {
            let glow = NSShadow()
            glow.shadowColor = eyeColour.withAlphaComponent(0.6)
            glow.shadowBlurRadius = span * 0.055
            glow.shadowOffset = .zero
            glow.set()
        }
        eyeColour.setFill()
        eyeColour.setStroke()

        for side in [-1.0, 1.0] as [CGFloat] {
            let lift = span * frame.headTilt * (side < 0 ? 1 : -1) * 0.35
            let eyeRect = NSRect(
                x: side < 0 ? centre.x - gap / 2 - eyeW : centre.x + gap / 2,
                y: centre.y - eyeH / 2 + lift,
                width: eyeW, height: eyeH
            )
            // Shut is continuous, so an eye folds into an arc rather than cutting.
            let shut = max(frame.squint, side < 0 ? frame.winkLeft : 0)
            drawEye(in: eyeRect, side: side, shut: shut, span: span)
            if frame.crossedOut > 0.01 {
                drawCross(in: eyeRect, span: span, alpha: frame.crossedOut)
            }
            if frame.brows > 0.01 {
                drawBrow(over: eyeRect, span: span, alpha: frame.brows)
            }
        }

        // The bars take the mouth's place rather than sitting under it: two
        // things in the same spot read as clutter, and a pet showing the music
        // where its mouth goes looks like it is singing along.
        if let spectrum, !spectrum.isSilent {
            drawSpectrum(spectrum, centre: centre, span: span)
        } else if abs(frame.mouth) > 0.01 {
            drawMouth(centre: centre, span: span)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    func drawEye(in eye: NSRect, side: CGFloat, shut: Double, span: CGFloat) {
        if shut < 0.995 {
            NSGraphicsContext.saveGraphicsState()
            if shut > 0.01 {
                eyeColour.withAlphaComponent(1 - shut).setFill()
            }
            let tilt = CGFloat(frame.tilt) * (side < 0 ? 1 : -1)
            if tilt != 0 {
                let spin = NSAffineTransform()
                spin.translateX(by: eye.midX, yBy: eye.midY)
                spin.rotate(byDegrees: tilt)
                spin.translateX(by: -eye.midX, yBy: -eye.midY)
                spin.concat()
            }
            // The eye closes by squashing toward its own centre, not by fading.
            let squashed = eye.insetBy(dx: 0, dy: eye.height * CGFloat(shut) * 0.5)
            // Soft to the point of being a squircle, which is what stops a wide
            // eye reading as a bar.
            let radius = min(squashed.width, squashed.height) * 0.48
            NSBezierPath(roundedRect: squashed, xRadius: radius, yRadius: radius).fill()

            NSGraphicsContext.restoreGraphicsState()
        }

        guard shut > 0.005 else { return }
        eyeColour.withAlphaComponent(shut).setStroke()
        let arc = NSBezierPath()
        arc.lineWidth = max(2, span * 0.042)
        arc.lineCapStyle = .round
        let radius = eye.width * 0.60
        let origin = NSPoint(x: eye.midX, y: eye.midY - radius * 0.30)
        arc.appendArc(withCenter: origin, radius: radius, startAngle: 25, endAngle: 155)
        arc.stroke()
        eyeColour.setStroke()
    }

    /// Two crossed strokes, the one shape that reads as thoroughly done in.
    func drawCross(in eye: NSRect, span: CGFloat, alpha: Double) {
        NSGraphicsContext.saveGraphicsState()
        // Over the eye, in the face colour, so the eye itself is struck through
        // rather than having a second mark sitting on top of it.
        NSShadow().set()
        Palette.faceBottom.withAlphaComponent(1).setStroke()
        let cut = NSBezierPath()
        cut.lineWidth = max(3, span * 0.05)
        cut.lineCapStyle = .round
        let inset = eye.insetBy(dx: -eye.width * 0.06, dy: -eye.height * 0.22)
        cut.move(to: NSPoint(x: inset.minX, y: inset.minY))
        cut.line(to: NSPoint(x: inset.maxX, y: inset.maxY))
        cut.move(to: NSPoint(x: inset.minX, y: inset.maxY))
        cut.line(to: NSPoint(x: inset.maxX, y: inset.minY))
        cut.stroke()
        NSGraphicsContext.restoreGraphicsState()

        eyeColour.withAlphaComponent(alpha).setStroke()
        let mark = NSBezierPath()
        mark.lineWidth = max(2, span * 0.038)
        mark.lineCapStyle = .round
        let box = eye.insetBy(dx: eye.width * 0.14, dy: -eye.height * 0.10)
        mark.move(to: NSPoint(x: box.minX, y: box.minY))
        mark.line(to: NSPoint(x: box.maxX, y: box.maxY))
        mark.move(to: NSPoint(x: box.minX, y: box.maxY))
        mark.line(to: NSPoint(x: box.maxX, y: box.minY))
        mark.stroke()
        eyeColour.setStroke()
    }

    func drawBrow(over eye: NSRect, span: CGFloat, alpha: Double) {
        eyeColour.withAlphaComponent(alpha).setStroke()
        let brow = NSBezierPath()
        brow.lineWidth = max(2, span * 0.034)
        brow.lineCapStyle = .round
        let radius = eye.width * 0.62
        let centre = NSPoint(x: eye.midX, y: eye.maxY + span * 0.02)
        brow.appendArc(withCenter: centre, radius: radius, startAngle: 40, endAngle: 140)
        brow.stroke()
        eyeColour.setStroke()
    }

    /// The bars, under the eyes where a mouth would be. Drawn from the middle
    /// outward so the low end sits in the centre, which is where a bass line
    /// belongs and keeps the shape symmetric whatever is playing.
    func drawSpectrum(_ spectrum: Spectrum, centre: CGPoint, span: CGFloat) {
        let bars = spectrum.bands
        guard !bars.isEmpty else { return }
        let width = span * 0.055
        let gap = span * 0.030
        let baseline = centre.y - span * 0.31
        let tallest = span * 0.26
        // Mirrored: low frequencies in the middle, highs at the outside.
        let mirrored = Array(bars.dropFirst().reversed()) + bars
        let total = CGFloat(mirrored.count) * width + CGFloat(mirrored.count - 1) * gap

        eyeColour.setFill()
        for (index, value) in mirrored.enumerated() {
            let height = max(width, tallest * CGFloat(value))
            let x = centre.x - total / 2 + CGFloat(index) * (width + gap)
            let bar = NSRect(x: x, y: baseline - height / 2, width: width, height: height)
            NSBezierPath(roundedRect: bar, xRadius: width / 2, yRadius: width / 2).fill()
        }
    }

    func drawMouth(centre: CGPoint, span: CGFloat) {
        // Open first: a mouth that is singing is a shape, not a line, and the
        // curve underneath would only fight it.
        if frame.openMouth > 0.01 {
            let open = CGFloat(frame.openMouth)
            let y = centre.y - span * 0.30
            let width = span * 0.20 * open
            let height = span * 0.20 * open
            let mouth = NSRect(x: centre.x - width / 2, y: y - height / 2,
                               width: width, height: height)
            eyeColour.withAlphaComponent(Double(open)).setFill()
            // Taller than it is wide at the corners: an oval reads as a yawn,
            // a rounded square reads as a held note.
            NSBezierPath(roundedRect: mouth, xRadius: width * 0.42,
                         yRadius: height * 0.42).fill()
            eyeColour.setFill()
            guard open < 0.99 else { return }
        }

        // Clear of the eyes even when one is lowered by a head tilt.
        let y = centre.y - span * 0.34
        let triangle = CGFloat(frame.triangle)

        if triangle > 0.01 {
            eyeColour.withAlphaComponent(Double(triangle)).setFill()
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
        eyeColour.withAlphaComponent(Double(1 - triangle)).setStroke()
        let curve = CGFloat(frame.mouth)
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
        eyeColour.setStroke()
    }
}
