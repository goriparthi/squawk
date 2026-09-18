import AppKit
import SquawkCore

/// The dial. One arc per request waiting on you, laid out clockwise from twelve
/// o'clock in arrival order, so the oldest is always the one at the top.
final class RingView: NSView {
    var roster = Roster() {
        didSet { needsDisplay = true }
    }

    var selectedID: String? {
        didSet { needsDisplay = true }
    }

    var onSelect: ((String) -> Void)?

    private let ringWidth: CGFloat = 16
    private let gap: CGFloat = 3

    override var isFlipped: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var center: CGPoint {
        CGPoint(x: bounds.midX, y: bounds.midY)
    }

    private var radius: CGFloat {
        (min(bounds.width, bounds.height) - ringWidth) / 2 - 2
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setLineCap(.butt)

        drawTrack(context)
        guard !roster.isEmpty else {
            drawCentre(primary: "clear", secondary: "no agent waiting")
            return
        }

        let slice = 360.0 / CGFloat(roster.count)
        for (index, entry) in roster.entries.enumerated() {
            let start = 90 - CGFloat(index) * slice - (roster.count > 1 ? gap / 2 : 0)
            let end = 90 - CGFloat(index + 1) * slice + (roster.count > 1 ? gap / 2 : 0)
            let isSelected = entry.id == selectedID
            draw(
                arcFrom: start,
                to: end,
                color: isSelected ? Palette.waitingBright : Palette.waiting,
                width: isSelected ? ringWidth + 4 : ringWidth,
                context: context
            )
        }

        let count = roster.count
        drawCentre(
            primary: "\(count)",
            secondary: count == 1 ? "waiting" : "waiting"
        )
    }

    private func drawTrack(_ context: CGContext) {
        context.setStrokeColor(Palette.track.cgColor)
        context.setLineWidth(ringWidth)
        context.addArc(
            center: center,
            radius: radius,
            startAngle: 0,
            endAngle: .pi * 2,
            clockwise: false
        )
        context.strokePath()
    }

    private func draw(arcFrom start: CGFloat, to end: CGFloat, color: NSColor, width: CGFloat, context: CGContext) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.addArc(
            center: center,
            radius: radius,
            startAngle: start * .pi / 180,
            endAngle: end * .pi / 180,
            clockwise: true
        )
        context.strokePath()
    }

    private func drawCentre(primary: String, secondary: String) {
        let primaryAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 34, weight: .medium),
            .foregroundColor: Palette.primaryText,
        ]
        let secondaryAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: Palette.secondaryText,
        ]

        let primaryText = NSAttributedString(string: primary, attributes: primaryAttributes)
        let secondaryText = NSAttributedString(string: secondary, attributes: secondaryAttributes)
        let primarySize = primaryText.size()
        let secondarySize = secondaryText.size()
        let block = primarySize.height + secondarySize.height + 2

        primaryText.draw(at: CGPoint(
            x: center.x - primarySize.width / 2,
            y: center.y + block / 2 - primarySize.height
        ))
        secondaryText.draw(at: CGPoint(
            x: center.x - secondarySize.width / 2,
            y: center.y + block / 2 - primarySize.height - secondarySize.height - 2
        ))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let id = entryID(at: point) else {
            super.mouseDown(with: event)
            return
        }
        selectedID = id
        onSelect?(id)
    }

    /// Hit testing is done in polar space: the click has to land inside the ring
    /// band, and the angle picks the slice.
    func entryID(at point: CGPoint) -> String? {
        guard !roster.isEmpty else { return nil }
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        let band = ringWidth / 2 + 6
        guard distance >= radius - band, distance <= radius + band else { return nil }

        var degrees = atan2(dy, dx) * 180 / .pi
        var offset = 90 - degrees
        if offset < 0 { offset += 360 }
        degrees = offset

        let slice = 360.0 / CGFloat(roster.count)
        let index = min(Int(degrees / slice), roster.count - 1)
        return roster.entries[index].id
    }
}

enum Palette {
    static let track = NSColor(calibratedWhite: 1, alpha: 0.08)
    static let waiting = NSColor(calibratedRed: 0.98, green: 0.71, blue: 0.24, alpha: 0.85)
    static let waitingBright = NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.36, alpha: 1.0)
    static let primaryText = NSColor(calibratedWhite: 0.96, alpha: 1)
    static let secondaryText = NSColor(calibratedWhite: 0.62, alpha: 1)
    static let panel = NSColor(calibratedWhite: 0.09, alpha: 0.96)
    static let deny = NSColor(calibratedRed: 0.94, green: 0.35, blue: 0.32, alpha: 1)
    static let allow = NSColor(calibratedRed: 0.36, green: 0.80, blue: 0.50, alpha: 1)
}
