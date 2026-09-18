import AppKit
import SceneKit
import SquawkCore

/// The modelled companion, live. A transparent SceneKit view that sits where
/// the drawn body used to, animating itself every frame: an idle sway, a walk
/// on and off the screen, and a dance.
@MainActor
final class CompanionView: SCNView, SCNSceneRendererDelegate {
    /// What the pet is doing, which decides what drives its joints.
    enum Activity: Equatable {
        case standing
        /// Walking on, from the given edge offset toward its place.
        case arriving(since: CFTimeInterval)
        case leaving(since: CFTimeInterval, then: () -> Void)
        case dancing(since: CFTimeInterval)

        static func == (lhs: Activity, rhs: Activity) -> Bool {
            switch (lhs, rhs) {
            case (.standing, .standing): true
            case let (.arriving(a), .arriving(b)): a == b
            case let (.leaving(a, _), .leaving(b, _)): a == b
            case let (.dancing(a), .dancing(b)): a == b
            default: false
            }
        }
    }

    /// Rubbed its tummy, and the same again twice over, which starts a dance.
    var onTummyRub: (() -> Void)?
    var onTummyDoubleClick: (() -> Void)?

    var pose: BodyPose = .pose(for: .calm) {
        didSet { if activity == .standing { built.apply(pose) } }
    }

    private let built = CompanionScene()
    private let face: FaceAnimator
    private var activity: Activity = .standing
    private var rub = TummyRub()
    private var tracking: NSTrackingArea?
    /// How far it has walked, for the stride, so stopping and starting again
    /// does not jerk the legs back to the start of a step.
    private var walked: Double = 0
    private var lastFrame: CFTimeInterval = 0

    init(face: FaceAnimator) {
        self.face = face
        super.init(frame: .zero, options: nil)
        scene = built.scene
        pointOfView = built.pointOfView
        delegate = self
        isPlaying = true
        rendersContinuously = true
        antialiasingMode = .multisampling4X
        autoenablesDefaultLighting = false
        // Transparent, or the pet arrives in a black box.
        backgroundColor = .clear
        wantsLayer = true
        layer?.isOpaque = false
        built.rest()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Rendering a pet nobody can see costs the same as rendering one they can.
    override func viewDidHide() {
        super.viewDidHide()
        setRunning(false)
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        setRunning(window != nil)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setRunning(window != nil && !isHiddenOrHasHiddenAncestor)
    }

    private func setRunning(_ running: Bool) {
        isPlaying = running
        rendersContinuously = running
        if running { lastFrame = 0 }
    }

    // MARK: - Activities

    func stand() {
        activity = .standing
        built.apply(pose)
        built.root.position = SCNVector3Zero
        built.tint(nil)
    }

    /// Walks on from the nearest edge. The offset is in scene units, negative
    /// for the left.
    func arrive(from offset: CGFloat) {
        entryOffset = offset
        activity = .arriving(since: CACurrentMediaTime())
    }

    /// Walks off and then calls back, so the window is only hidden once the pet
    /// has actually left rather than vanishing mid stride.
    func leave(toward offset: CGFloat, then finished: @escaping () -> Void) {
        entryOffset = offset
        activity = .leaving(since: CACurrentMediaTime(), then: finished)
    }

    func dance() {
        activity = .dancing(since: CACurrentMediaTime())
    }

    var isDancing: Bool {
        if case .dancing = activity { return true }
        return false
    }

    private var entryOffset: CGFloat = -3

    // MARK: - The loop

    nonisolated func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {
        Task { @MainActor in self.step(at: time) }
    }

    private func step(at now: CFTimeInterval) {
        let dt = lastFrame == 0 ? 0 : min(now - lastFrame, 1.0 / 20)
        lastFrame = now

        face.advance(to: now)
        built.paintFace(face.artist)

        switch activity {
        case .standing:
            idle(at: now)
        case .arriving(let since):
            travel(elapsed: now - since, from: entryOffset, to: 0, at: now, dt: dt)
        case .leaving(let since, let finished):
            let done = travel(elapsed: now - since, from: 0, to: entryOffset, at: now, dt: dt)
            if done {
                activity = .standing
                finished()
            }
        case .dancing(let since):
            let elapsed = now - since
            built.apply(Dance.frame(at: elapsed))
            if elapsed > Dance.duration { stand() }
        }
    }

    /// Standing is not still: a slow breath and a sway, or it reads as a
    /// screenshot of a robot rather than one.
    private func idle(at now: CFTimeInterval) {
        let breath = sin(now * 1.1)
        built.root.position.y = CGFloat(breath) * 0.012
        built.bodyPivot.eulerAngles.z = CompanionScene.radians(sin(now * 0.55) * 1.4)
        built.headPivot.eulerAngles.y = CompanionScene.radians(sin(now * 0.37) * 5)
    }

    /// One step of a walk between two places. Returns true once it has arrived.
    @discardableResult
    private func travel(
        elapsed: TimeInterval, from: CGFloat, to: CGFloat,
        at now: CFTimeInterval, dt: TimeInterval
    ) -> Bool {
        let progress = min(1, elapsed / Entrance.duration)
        let eased = Entrance.progress(at: elapsed)
        built.root.position.x = from + (to - from) * CGFloat(eased)

        walked += dt
        // It slows as it arrives, and the legs slow with it, which is the whole
        // point of driving the stride from a phase rather than a timer.
        let effort = progress < 1 ? 1.0 : 0.0
        built.apply(Gait.stride(phase: Gait.phase(at: walked), effort: effort))
        // Facing the way it is going.
        built.bodyPivot.eulerAngles.y = CompanionScene.radians(to > from ? 16 : -16)
        if progress >= 1 {
            built.apply(pose)
            built.bodyPivot.eulerAngles.y = 0
            return true
        }
        return false
    }

    // MARK: - Pointing at it

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
                                  owner: self)
        addTrackingArea(area)
        tracking = area
    }

    /// Only the pet takes clicks. Everything around it is window, and the
    /// window is transparent, so those clicks belong to what is behind.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return isOnThePet(local) ? self : nil
    }

    private func isOnThePet(_ point: NSPoint) -> Bool {
        !hitTest(point, options: [.searchMode: SCNHitTestSearchMode.any.rawValue]).isEmpty
    }

    /// The tummy is the body, which is the one part with no other job.
    private func isTummy(_ point: NSPoint) -> Bool {
        hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
            .contains { $0.node.parent === built.bodyPivot }
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        guard isTummy(point) else {
            rub.reset()
            return
        }
        if rub.track(x: point.x) { onTummyRub?() }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        rub.reset()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, isTummy(point) {
            onTummyDoubleClick?()
            return
        }
        super.mouseDown(with: event)
    }
}
