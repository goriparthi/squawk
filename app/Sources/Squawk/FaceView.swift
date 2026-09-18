import AppKit
import SquawkCore

/// The dial's face. Driven by a display link rather than discrete property
/// changes: every value is interpolated, so expressions morph instead of
/// snapping, which is the difference between a companion and a status light.
final class FaceView: NSView {
    /// Shared with the modelled companion when one is on screen, so the two
    /// blink together rather than each keeping its own clock.
    let animator: FaceAnimator

    var expression: FaceExpression {
        get { animator.expression }
        set {
            guard newValue != animator.expression else { return }
            animator.expression = newValue
            wake()
        }
    }

    private var link: CADisplayLink?

    init(animator: FaceAnimator = FaceAnimator()) {
        self.animator = animator
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var isFlipped: Bool { false }
    /// The face is drawn over the dial; clicks belong to what is beneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window == nil || isHiddenOrHasHiddenAncestor ? stop() : start()
    }

    // The animator is shared with the modelled companion, and two drivers
    // stepping it would run the blink at double speed. Whichever face is on
    // screen owns the clock.
    override func viewDidHide() {
        super.viewDidHide()
        stop()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        if window != nil { start() }
    }

    private func start() {
        guard link == nil else { return }
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        animator.resume()
    }

    private func stop() {
        link?.invalidate()
        link = nil
    }

    /// Jumps straight to the target, for an offscreen render with no clock.
    func settle() {
        animator.settle()
        needsDisplay = true
    }

    private func wake() {
        if link == nil, window != nil { start() }
        needsDisplay = true
    }

    @objc private func tick(_ sender: CADisplayLink) {
        animator.advance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        animator.artist.draw(in: bounds)
    }
}
