import AppKit
import SceneKit
import SquawkCore

/// The modelled companion, live. A transparent SceneKit view that sits where
/// the drawn body used to, animating itself every frame: an idle sway, a walk
/// on and off the screen, and a dance.
@MainActor
final class CompanionView: SCNView {
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
    /// Prodded anywhere on it. The flat dial had this on its ring, which is
    /// hidden when the companion is modelled, so the model has to offer it or
    /// clicking the pet does nothing at all.
    var onPoke: (() -> Void)?

    /// The mood to settle into when it is not doing anything else. Set from
    /// the app; the springs decide how it gets there.
    var pose: BodyPose = .pose(for: .calm)

    private let built: CompanionScene
    private let face: FaceAnimator
    private var activity: Activity = .standing
    private var rub = TummyRub()
    private var tracking: NSTrackingArea?
    /// How far it has walked, for the stride, so stopping and starting again
    /// does not jerk the legs back to the start of a step.
    private var springs = PoseSpring()
    private var walked: Double = 0
    private var lastFrame: CFTimeInterval = 0
    private var lastFacePaint: CFTimeInterval = 0
    private var lastFaceSignature = 0
    /// What is playing, smoothed here rather than in the audio thread so the
    /// bars settle at the frame rate they are drawn at.
    private var spectrum = Spectrum.silent
    private var wanted = Spectrum.silent
    private var beats = BeatDetector()
    private var presence = MusicPresence()
    private var lastBeatAt: CFTimeInterval = -1
    private var link: CADisplayLink?

    init(face: FaceAnimator, persona: Persona = Cast.default) {
        self.face = face
        built = CompanionScene(persona: persona)
        face.restingEye = FaceTint(persona.eye.red, persona.eye.green, persona.eye.blue)
        super.init(frame: .zero, options: nil)
        scene = built.scene
        pointOfView = built.pointOfView
        isPlaying = true
        rendersContinuously = true
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = Self.restingFrameRate
        autoenablesDefaultLighting = false
        // Transparent, or the pet arrives in a black box.
        backgroundColor = .clear
        wantsLayer = true
        layer?.isOpaque = false
        built.apply(Pose3D())
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
        running ? startLoop() : stopLoop()
    }

    // MARK: - Activities

    func stand() {
        activity = .standing
        built.tint(nil)
        // 360 degrees round is the same way up as none, so it settles from
        // where it is rather than rewinding the turn it just did.
        springs.unwindSpin()
    }

    /// Walks on from the nearest edge. The offset is in scene units, negative
    /// for the left.
    func arrive(from offset: CGFloat) {
        entryOffset = offset
        walked = 0
        // It starts offscreen rather than springing in from wherever it was
        // standing, which would be a slide rather than a walk.
        var start = Gait.pose(phase: 0, effort: 0)
        start.travel = Double(offset)
        springs.reset(to: start)
        built.apply(start)
        activity = .arriving(since: CACurrentMediaTime())
    }

    /// Walks off and then calls back, so the window is only hidden once the pet
    /// has actually left rather than vanishing mid stride.
    func leave(toward offset: CGFloat, then finished: @escaping () -> Void) {
        entryOffset = offset
        activity = .leaving(since: CACurrentMediaTime(), then: finished)
    }

    /// Starts the routine, or stops it if it is already going.
    func toggleDance() {
        if isDancing {
            stand()
        } else {
            activity = .dancing(since: CACurrentMediaTime())
        }
    }

    /// Lights the microphone and camera lamp.
    func light(_ state: PrivacyState) {
        built.light(state)
    }

    /// Something is playing and it has found the pulse of it.
    var isHearingMusic: Bool { presence.isPlaying }

    var isDancing: Bool {
        if case .dancing = activity { return true }
        return false
    }

    private var entryOffset: CGFloat = -3

    /// Everything the display can show, for the moments worth it: a walk, a
    /// dance, a reaction. The default caps at 60 and leaves half the frames of
    /// a ProMotion panel on the table.
    static var fullFrameRate: Int { NSScreen.main?.maximumFramesPerSecond ?? 60 }
    /// Standing still is a breath and a slow sway. Rendering that twice as
    /// often costs a noticeable share of a core all day and looks identical.
    static let restingFrameRate = 30

    /// Raised while something is actually moving, and dropped again once it
    /// settles, so the pet is smooth when it matters and cheap when it is not.
    private func matchFrameRate(to activity: Activity) {
        let busy = activity != .standing
        let wanted = busy ? Self.fullFrameRate : Self.restingFrameRate
        guard preferredFramesPerSecond != wanted else { return }
        preferredFramesPerSecond = wanted
    }

    /// What the machine is playing. Nil stops it listening.
    func hear(_ heard: Spectrum?) {
        wanted = heard ?? .silent
        guard let heard, !heard.isSilent else {
            beats.reset()
            return
        }
        if beats.track(heard, at: CACurrentMediaTime()) {
            lastBeatAt = CACurrentMediaTime()
        }
        // Music is worth the full frame rate: bars drawn at 30 look stepped,
        // and a nod that lands a frame late lands off the beat.
        quicken(for: 1.2)
    }

    /// Runs at full rate for a moment, for a reaction that is over before a
    /// resting frame rate would have drawn it.
    func quicken(for seconds: TimeInterval = 1.6) {
        preferredFramesPerSecond = Self.fullFrameRate
        quickenUntil = CACurrentMediaTime() + seconds
    }

    private var quickenUntil: CFTimeInterval = 0

    /// Long enough to take three unhurried strides. `Entrance.duration` times a
    /// nudge on screen, which is far too quick to read as walking at all.
    static let walkDuration: TimeInterval = 3 / Gait.cadence

    // MARK: - The loop

    /// Driven from a display link on the main thread rather than from
    /// SceneKit's render delegate. The delegate runs on the render thread, so
    /// reaching main actor state from it meant hopping through a Task, and the
    /// pose landed a frame or two after the frame it was computed for. Every
    /// frame then rendered slightly stale joints, which is judder.
    private func startLoop() {
        guard link == nil, window != nil else { return }
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        lastFrame = 0
        face.resume()
    }

    private func stopLoop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ sender: CADisplayLink) {
        step(at: CACurrentMediaTime())
    }

    private func step(at now: CFTimeInterval) {
        let dt = lastFrame == 0 ? 0 : min(now - lastFrame, 1.0 / 20)
        lastFrame = now

        spectrum = SpectrumMeter.follow(spectrum, toward: wanted, dt: dt)
        let playing = presence.update(spectrum, at: now)
        if built.headphones.isHidden == playing { built.headphones.isHidden = !playing }
        // On the chest, not the face: the eyes and the mouth have a job already,
        // and a meter over the mouth read as clutter.
        built.show(playing ? spectrum : nil)

        face.advance(to: now)
        // The body is worth every frame the display has; the eyes are not. A
        // face redrawn and uploaded at the full frame rate cost three quarters
        // of this view's CPU, so it is capped, and skipped outright when the
        // face would come out the same as the one already on the head.
        if now - lastFacePaint >= 1.0 / 30 {
            let artist = face.artist
            let signature = artist.signature
            if signature != lastFaceSignature {
                lastFaceSignature = signature
                built.paintFace(artist)
            }
            lastFacePaint = now
        }

        // One target pose a frame, whatever it is doing, then one set of
        // springs between that and the joints. Nothing writes an angle
        // directly, so every change carries momentum and nothing can snap.
        var target: Pose3D
        switch activity {
        case .standing:
            target = idle(at: now)
        case .arriving(let since):
            target = travel(elapsed: now - since, from: entryOffset, to: 0, dt: dt)
        case .leaving(let since, let finished):
            target = travel(elapsed: now - since, from: 0, to: entryOffset, dt: dt)
            if now - since >= Self.walkDuration {
                activity = .standing
                finished()
            }
        case .dancing(let since):
            // Loops from the top rather than stopping: a dance ends when you
            // tap the belly again, not when a timer runs out under it. And it
            // runs at the tempo of whatever is playing when anything is.
            let elapsed = now - since
            target = Dance.pose(at: elapsed, tempo: Dance.danceable(beats.tempo))
            built.tint(hue: Dance.frame(at: elapsed).hue)
        }
        target = movedToTheBeat(target, at: now)
        built.apply(springs.step(toward: target, dt: dt))
        if now >= quickenUntil { matchFrameRate(to: activity) }
    }

    /// Nods, dips and bounces on the beat, over whatever else it is doing. A
    /// pet that only shows a meter is a gauge; one that moves to the music is
    /// listening to it.
    private func movedToTheBeat(_ pose: Pose3D, at now: CFTimeInterval) -> Pose3D {
        guard lastBeatAt >= 0, presence.isPlaying else { return pose }
        let pulse = BeatDetector.pulse(since: now - lastBeatAt)
        guard pulse > 0.001 else { return pose }
        var moved = pose
        // Down on the beat, not up: weight drops onto it.
        moved.bob -= pulse * 0.03
        moved.headPitch += pulse * 7
        moved.lean += pulse * 2.5
        // The knees take the drop, or the feet leave the ground.
        moved.leftKnee += pulse * 7
        moved.rightKnee += pulse * 7
        // And the arms lift with it, gently, unless they are already busy.
        if !isDancing {
            moved.leftShoulder += pulse * 9
            moved.rightShoulder += pulse * 9
        }
        return moved
    }

    /// Standing is not still. A breath, a shift of weight and a wandering head,
    /// none of them in step with each other, because a body whose parts share
    /// one period reads as a mechanism.
    private func idle(at now: CFTimeInterval) -> Pose3D {
        var target = pose.pose3D()
        let breath = sin(now * 0.9)
        target.bob += breath * 0.010
        target.lean += breath * 0.7
        target.sway += sin(now * 0.37) * 1.5
        target.headYaw += sin(now * 0.29) * 6
        target.headRoll += sin(now * 0.23 + 1.1) * 2.5
        target.headPitch += breath * 1.2
        // The arms hang off a breathing body rather than being held in place.
        let float = Double(pose.liveliness)
        target.leftShoulder += sin(now * 0.61) * 2.2 * float
        target.rightShoulder += sin(now * 0.61 + 0.8) * 2.2 * float
        target.travel = 0
        return target
    }

    /// One frame of a walk between two places.
    private func travel(
        elapsed: TimeInterval, from: CGFloat, to: CGFloat, dt: TimeInterval
    ) -> Pose3D {
        let progress = min(1, elapsed / Self.walkDuration)
        // It works up to a stride and settles out of one, rather than the legs
        // switching on and off. This is the whole point of driving the stride
        // from a phase and an effort rather than from a timer.
        let effort = min(1, progress * 5, (1 - progress) * 4)
        // The feet only cover ground while they are actually striding, so it
        // never slides the last inch with its legs already still.
        walked += dt * effort

        var target = Gait.pose(phase: Gait.phase(at: walked), effort: effort)
        let eased = Entrance.progress(at: min(1, progress) * Entrance.duration)
        target.travel = Double(from + (to - from) * CGFloat(eased))
        // Turned toward where it is going, and square on again once it stops.
        target.spin = (to > from ? 15 : -15) * effort
        return target
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
        guard isOnThePet(point) else {
            super.mouseDown(with: event)
            return
        }
        // Dragged rather than clicked, which is how the window is moved.
        let start = event.locationInWindow
        let ended = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged])
        if let ended, ended.type == .leftMouseDragged {
            super.mouseDown(with: event)
            return
        }
        let moved = ended.map {
            abs($0.locationInWindow.x - start.x) + abs($0.locationInWindow.y - start.y)
        } ?? 0
        if moved < 4 { onPoke?() }
    }
}
