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

/// The window is square; only this circle is painted. macOS routes mouse events
/// by the window's alpha, so the untouched corners genuinely click through to
/// whatever is behind rather than swallowing the click.
final class CircleBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let diameter = min(bounds.width, bounds.height) - 2
        let circle = NSRect(
            x: bounds.midX - diameter / 2,
            y: bounds.midY - diameter / 2,
            width: diameter,
            height: diameter
        )
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

    /// Outside the circle the window is transparent, so the click belongs to the
    /// app underneath. Without this the square frame would still eat it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let radius = (min(bounds.width, bounds.height) - 2) / 2
        let dx = local.x - bounds.midX
        let dy = local.y - bounds.midY
        guard dx * dx + dy * dy <= radius * radius else { return nil }
        return super.hitTest(point)
    }
}

/// Buttons in a non-activating panel are clicked while another app owns focus,
/// so each one has to opt into acting on the first press.
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
