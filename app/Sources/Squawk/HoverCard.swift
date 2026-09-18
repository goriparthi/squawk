import AppKit
import SquawkCore

/// The full command, shown beside the dial while you hover an arc. The circle
/// only has room for a truncated line, and approving something you cannot read
/// is the one failure this whole app exists to prevent.
@MainActor
final class HoverCard {
    private let panel: NSPanel
    private let projectLabel = NSTextField(labelWithString: "")
    private let commandLabel = NSTextField(labelWithString: "")
    private let width: CGFloat = 300

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let background = CardBackgroundView()
        projectLabel.font = Palette.ui(size: 11, weight: .semibold)
        projectLabel.textColor = Palette.secondaryText
        commandLabel.font = Palette.telemetry(size: 11)
        commandLabel.textColor = Palette.primaryText
        commandLabel.lineBreakMode = .byWordWrapping
        commandLabel.maximumNumberOfLines = 4
        commandLabel.preferredMaxLayoutWidth = width - 28

        let stack = NSStackView(views: [projectLabel, commandLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 11),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -11),
        ])
        panel.contentView = background
    }

    func show(_ request: PendingRequest, besides parent: NSWindow) {
        projectLabel.stringValue = "\(request.project)  \u{00B7}  \(request.tool)"
        commandLabel.stringValue = request.summary

        guard let background = panel.contentView else { return }
        background.layoutSubtreeIfNeeded()
        let height = background.fittingSize.height
        panel.setContentSize(NSSize(width: width, height: height))

        // Sit to the right of the dial, or flip to the left when the screen runs
        // out, so the card is never half off the display.
        let frame = parent.frame
        var origin = NSPoint(x: frame.maxX + 10, y: frame.midY - height / 2)
        if let screen = parent.screen ?? NSScreen.main,
           origin.x + width > screen.visibleFrame.maxX {
            origin.x = frame.minX - width - 10
        }
        panel.setFrameOrigin(origin)
        panel.orderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private final class CardBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        Palette.panel.setFill()
        path.fill()
        Palette.line.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
