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
    /// Fires with the arc under the pointer, or nil when it leaves the band.
    var onHover: ((String?) -> Void)?
    /// Whether the pointer is over the dial at all, which drives fade to solid.
    var onMouseInside: ((Bool) -> Void)?
    /// A click on the dial that was not an arc and did not drag it.
    var onPoke: (() -> Void)?
    private var pressedAt: NSPoint?
    private var hovered: String?
    private var tracking: NSTrackingArea?

    /// Drives the band weight and the centre readout, so the dial keeps its
    /// proportions at any diameter the slider lands on.
    var diameter: CGFloat = DialSize.default.diameter {
        didSet { needsDisplay = true }
    }

    private var ringWidth: CGFloat { DialGeometry.ringWidth(diameter) }
    private let gap: CGFloat = 3
    /// The gap that separates one agent from the next. Wider than the gap
    /// between two of one agent's calls, because otherwise the grouping is an
    /// order nobody can actually see on the ring.
    private let sessionGap: CGFloat = 11

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
        // The face carries the cleared state now, so the centre text would be
        // saying the same thing twice.
        guard !roster.isEmpty else { return }

        let slice = 360.0 / CGFloat(roster.count)
        // Grouped, so one agent's calls are one cluster rather than arcs
        // scattered round the ring in whatever order they happened to land.
        let entries = roster.grouped
        let breaks = roster.sessionBreaks
        for (index, entry) in entries.enumerated() {
            let opening = breaks.contains(index) ? sessionGap : gap
            let closing = breaks.contains((index + 1) % max(entries.count, 1)) ? sessionGap : gap
            let start = 90 - CGFloat(index) * slice - (roster.count > 1 ? opening / 2 : 0)
            let end = 90 - CGFloat(index + 1) * slice + (roster.count > 1 ? closing / 2 : 0)
            let isSelected = entry.id == selectedID
            // Amber is a decision to make; blue is a session that simply wants
            // you, which you cannot answer from here.
            let base = entry.request.awaitsDecision ? Palette.waiting : Palette.running
            draw(
                arcFrom: start,
                to: end,
                color: isSelected ? base.blended(withFraction: 0.35, of: .white) ?? base : base,
                width: isSelected ? ringWidth + 4 : ringWidth,
                context: context
            )
        }

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
            .font: Palette.telemetry(size: DialGeometry.centreFontSize(diameter), weight: .medium),
            .foregroundColor: Palette.primaryText,
        ]
        let secondaryAttributes: [NSAttributedString.Key: Any] = [
            .font: Palette.ui(size: DialGeometry.captionFontSize(diameter)),
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        let id = entryID(at: convert(event.locationInWindow, from: nil))
        guard id != hovered else { return }
        hovered = id
        onHover?(id)
    }

    override func mouseEntered(with event: NSEvent) {
        onMouseInside?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onMouseInside?(false)
        guard hovered != nil else { return }
        hovered = nil
        onHover?(nil)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let id = entryID(at: point) else {
            // Might be a poke, might be the start of a drag. Which one is only
            // known on mouse up, so the decision waits until then.
            pressedAt = event.locationInWindow
            super.mouseDown(with: event)
            return
        }
        pressedAt = nil
        selectedID = id
        onSelect?(id)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressedAt = nil }
        super.mouseUp(with: event)
        guard let start = pressedAt else { return }
        let end = event.locationInWindow
        let moved = hypot(end.x - start.x, end.y - start.y)
        // Dragging the dial somewhere is not prodding it.
        if moved < 4 { onPoke?() }
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
        // The same order the arcs were drawn in. Hit testing the arrival order
        // while drawing the grouped one selects a different arc from the one
        // under the pointer, which is the worst kind of bug on an approval UI.
        return roster.grouped[index].id
    }
}

/// The brand palette. Values come from design/squawk_design_tokens.json, which
/// is the source of truth; change them there and mirror the change here.
enum Palette {
    static func hex(_ value: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha
        )
    }

    static let radarBlack = hex(0x070B0D)
    static let panel = hex(0x0C1317, alpha: 0.97)
    static let surface = hex(0x121C21)
    static let line = hex(0x26363D)
    static let primaryText = hex(0xE9F1F2)
    static let secondaryText = hex(0x8FA3AA)
    static let brand = hex(0x67E8D0)

    // State colours carry meaning, so they are named for the state not the hue.
    static let waiting = hex(0xF6B94E)
    static let waitingBright = hex(0xFFD083)
    static let running = hex(0x4FC7FF)
    static let error = hex(0xFF5B5B)
    static let complete = hex(0x5CE1A5)

    static let track = hex(0x26363D, alpha: 0.55)

    /// The dial face. Lighter than the panel token on purpose: the face has to
    /// separate from whatever is behind it, including a black desktop.
    static let faceTop = hex(0x17242B)
    static let faceBottom = hex(0x0E171C)
    static let rim = hex(0x3A4F58)
    /// The shell is lighter than the scope, which is what makes the scope read
    /// as an inset screen rather than the whole head.
    static let shellTop = hex(0x2C3D46)
    static let shellBottom = hex(0x1A262D)
    static let shellHighlight = hex(0x5C7480, alpha: 0.55)
    static let innerRim = hex(0x1D2C33)
    static let allow = complete
    static let deny = error

    /// Inter and IBM Plex Mono per the brand kit, falling back to the system
    /// faces when they are not installed rather than silently picking Helvetica.
    static func ui(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if let inter = NSFont(name: "Inter", size: size) {
            return NSFontManager.shared.convert(inter, toHaveTrait: weight >= .semibold ? .boldFontMask : [])
        }
        return .systemFont(ofSize: size, weight: weight)
    }

    static func telemetry(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont(name: "IBMPlexMono", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: weight)
    }
}
