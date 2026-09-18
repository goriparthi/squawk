import AppKit
import SquawkCore

/// The floating dock. A non-activating panel so answering it never takes focus
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
    }

    // Borderless panels refuse key status by default, which would leave the
    // keyboard shortcuts dead.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Rounded, translucent backdrop. Drawn rather than composed from a visual
/// effect view so the corner radius and the border stay in one place.
final class PanelBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18)
        Palette.panel.setFill()
        path.fill()
        Palette.line.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// Buttons in a non-activating panel are clicked while another app owns focus,
/// so each one has to opt into acting on the first press.
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
