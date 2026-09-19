import AppKit
import MetalKit
import SceneKit
import SquawkCore

/// The modelled companion, live. A transparent Metal view that sits where the
/// drawn body used to, posed and drawn once a frame by the loop below: an idle
/// sway, a walk on and off the screen, and a dance. SceneKit renders it but
/// does not drive it; see `init` for why.
@MainActor
final class CompanionView: MTKView {
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

    /// Rubbed its tummy, tapped it once (a giggle), and tapped it twice, which
    /// starts a dance.
    var onTummyRub: (() -> Void)?
    var onGiggle: (() -> Void)?
    var onTummyDoubleClick: (() -> Void)?
    private var giggleStartedAt: CFTimeInterval = -1
    /// Whether it sways along to whatever is playing. Turned off while it is
    /// saying something with its body: the groove blends over the pose, so a
    /// refusal pointed at you came out halfway back to a wiggle.
    var grooves = true

    /// How wide its mouth should be open this frame, asked once a frame. Set
    /// by whatever is speaking; nil when nothing is.
    var speechLevel: (() -> Double)?

    /// Prodded anywhere on it. The flat dial had this on its ring, which is
    /// hidden when the companion is modelled, so the model has to offer it or
    /// clicking the pet does nothing at all.
    var onPoke: (() -> Void)?

    /// The mood to settle into when it is not doing anything else. Set from
    /// the app; the springs decide how it gets there.
    var pose: BodyPose = .pose(for: .calm)

    private let built: CompanionScene
    private let face: FaceAnimator
    private let renderer: SCNRenderer
    private let queue: MTLCommandQueue?
    private var activity: Activity = .standing
    private var rub = TummyRub()
    /// Where a press landed, kept until the mouse comes up: as on the dial,
    /// what a click meant is only known then.
    private var pressed: (start: NSPoint, onPet: Bool, onTummy: Bool)?
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
    /// The character's own eye colour, to come back to when the music stops.
    private let restingEye: FaceTint
    private var lastHueAt: CFTimeInterval = 0
    private var wasPlaying = false
    private var lastBeatAt: CFTimeInterval = -1
    private var link: CADisplayLink?

    init(face: FaceAnimator, persona: Persona = Cast.default) {
        self.face = face
        built = CompanionScene(persona: persona)
        restingEye = FaceTint(persona.eye.red, persona.eye.green, persona.eye.blue)
        face.restingEye = restingEye
        let device = MTLCreateSystemDefaultDevice()
        renderer = SCNRenderer(device: device, options: nil)
        queue = device?.makeCommandQueue()
        super.init(frame: .zero, device: device)
        renderer.scene = built.scene
        renderer.pointOfView = built.pointOfView
        renderer.autoenablesDefaultLighting = false
        // Drawn only when the pose loop asks, so that loop's display link is
        // the frame rate. `SCNView` kept a link of its own and drew 118 frames
        // a second when asked for 60, and 24 when asked for 30, on a 120Hz
        // panel, whatever it was told about playing or rendering continuously.
        // Music cost 40% of a core that way; the rate is the whole bill.
        isPaused = true
        enableSetNeedsDisplay = true
        sampleCount = 4
        depthStencilPixelFormat = .depth32Float
        // sRGB, or SceneKit's linear output lands unencoded and the slate
        // grey shell comes out black.
        colorPixelFormat = .bgra8Unorm_srgb
        // Transparent, or the pet arrives in a black box.
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        layer?.isOpaque = false
        built.apply(Pose3D())
    }

    /// One frame, when the loop has posed one. SceneKit renders into the
    /// view's own drawable, multisampled and resolved by the pass descriptor.
    override func draw(_ dirtyRect: NSRect) {
        guard let queue, let drawable = currentDrawable, let pass = currentRenderPassDescriptor,
              let buffer = queue.makeCommandBuffer()
        else { return }
        renderer.render(atTime: lastFrame, viewport: CGRect(origin: .zero, size: drawableSize),
                        commandBuffer: buffer, passDescriptor: pass)
        buffer.present(drawable)
        buffer.commit()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not supported") }

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
    func arrive(from offset: CGFloat, at now: CFTimeInterval = CACurrentMediaTime()) {
        entryOffset = offset
        walked = 0
        // It starts offscreen rather than springing in from wherever it was
        // standing, which would be a slide rather than a walk.
        var start = Gait.pose(phase: 0, effort: 0)
        start.travel = Double(offset)
        springs.reset(to: start)
        built.apply(start)
        activity = .arriving(since: now)
    }

    /// Walks off and then calls back, so the window is only hidden once the pet
    /// has actually left rather than vanishing mid stride.
    func leave(toward offset: CGFloat, then finished: @escaping () -> Void) {
        entryOffset = offset
        activity = .leaving(since: CACurrentMediaTime(), then: finished)
    }

    /// Starts the routine, or stops it if it is already going.
    func toggleDance(at now: CFTimeInterval = CACurrentMediaTime()) {
        if isDancing {
            stand()
        } else {
            activity = .dancing(since: now)
        }
    }

    /// Lights the microphone and camera lamp.
    func light(_ state: PrivacyState) {
        built.light(state)
    }

    /// How lit its ears are, 0 to 1, while it is listening to you.
    var listening: Double = 0 {
        didSet {
            guard listening != oldValue else { return }
            built.listen(listening)
        }
    }

    /// Something is playing and it has found the pulse of it.
    var isHearingMusic: Bool { presence.isPlaying }

    /// The tempo it has settled on, in beats per minute, once it is sure.
    var heardTempo: Int? {
        guard let tempo = beats.tempo else { return nil }
        return Int((tempo * 60).rounded())
    }

    var isDancing: Bool {
        if case .dancing = activity { return true }
        return false
    }

    private var entryOffset: CGFloat = -3

    /// Everything the display can show, for the moments worth it: a walk, a
    /// dance, a reaction. The default caps at 60 and leaves half the frames of
    /// a ProMotion panel on the table.
    static var fullFrameRate: Int { NSScreen.main?.maximumFramesPerSecond ?? 60 }
    static let restingFrameRate = FramePace.resting

    /// Chosen from what it is doing, every frame, rather than pinned by whoever
    /// last asked for speed. `FramePace` holds the rule; this applies it.
    private func matchFrameRate(to activity: Activity, listening: Bool) {
        setFrameRate(FramePace.rate(moving: activity != .standing, listening: listening,
                                    displayMax: Self.fullFrameRate))
    }

    /// The display link that poses the joints is the frame rate: SceneKit draws
    /// once per pose. Left to itself the link follows the panel's own rate.
    private func setFrameRate(_ rate: Int) {
        guard let link, link.preferredFrameRateRange.preferred != Float(rate) else { return }
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: Float(rate), maximum: Float(rate), preferred: Float(rate))
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
    }

    /// Runs at full rate for a moment, for a reaction that is over before a
    /// resting frame rate would have drawn it.
    func quicken(for seconds: TimeInterval = 1.6) {
        setFrameRate(Self.fullFrameRate)
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
        setFrameRate(FramePace.rate(moving: activity != .standing, listening: presence.isPlaying,
                                    displayMax: Self.fullFrameRate))
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

    /// One frame at a chosen moment, for running the loop headless.
    func advance(to now: CFTimeInterval) { step(at: now) }
    var scene: SCNScene { built.scene }
    /// Every joint angle in degrees about x, to find one that has run away.
    var jointReport: [(String, Double)] { built.jointReport }

    private func step(at now: CFTimeInterval) {
        let dt = lastFrame == 0 ? 0 : min(now - lastFrame, 1.0 / 20)
        lastFrame = now

        spectrum = SpectrumMeter.follow(spectrum, toward: wanted, dt: dt)
        let playing = presence.update(spectrum, at: now)
        if built.headphones.isHidden == playing { built.headphones.isHidden = !playing }
        // On the chest, not the face: the eyes and the mouth have a job already,
        // and a meter over the mouth read as clutter.
        built.show(playing ? spectrum : nil)

        // While it listens, the eyes drift round the colour wheel. Stepped at a
        // few times a second rather than every frame: the animator interpolates
        // between them, so this decides where the colour is going, not how it
        // gets there.
        if playing {
            if now - lastHueAt >= FaceTint.hueStep {
                lastHueAt = now
                face.restingEye = FaceTint.hue(now / FaceTint.hueCycle)
            }
            wasPlaying = true
        } else if wasPlaying {
            wasPlaying = false
            face.restingEye = restingEye
        }

        face.talking = speechLevel?() ?? 0
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
            Giggle.apply(to: &target, at: now - giggleStartedAt)
        case .arriving(let since):
            target = travel(elapsed: now - since, from: entryOffset, to: 0, dt: dt)
            // The walk has to end, or it is "moving" for the rest of the day:
            // drawn at the display maximum, never breathing, never grooving,
            // and never taking the pose the app sets. It did exactly that.
            if now - since >= Self.walkDuration { stand() }
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
        if now >= quickenUntil { matchFrameRate(to: activity, listening: playing) }
        needsDisplay = true
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
        moved.bob -= pulse * 0.014
        moved.headPitch += pulse * 3.5
        moved.lean += pulse * 1.2
        // The knees take the drop, or the feet leave the ground.
        moved.leftKnee += pulse * 3.5
        moved.rightKnee += pulse * 3.5
        // And the arms lift with it, gently, unless they are already busy.
        if !isDancing {
            moved.leftShoulder += pulse * 4
            moved.rightShoulder += pulse * 4
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

        // With music on it does not merely stand there nodding: it grooves, in
        // time with the track rather than to a timer of its own. The phase runs
        // from the last beat at the detected tempo, so the sway lands where the
        // beats do and a slow track sways slowly.
        if grooves, presence.isPlaying, lastBeatAt >= 0 {
            let tempo = Dance.danceable(beats.tempo)
            let beat = (now - lastBeatAt) * tempo
            target = target.blended(with: Dance.groove(beat: beat),
                                    amount: Dance.grooveWeight)
        }
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

    func isOnThePet(_ point: NSPoint) -> Bool {
        !hits(at: point, mode: .any).isEmpty
    }

    /// The tummy is the body mesh and nothing else: the badge, meter, lamp and
    /// shoulder pads hang off the same pivot, and matching on the pivot made a
    /// double tap on a shoulder a dance.
    func isTummy(_ point: NSPoint) -> Bool {
        hits(at: point, mode: .all).contains { $0.node === built.body }
    }

    /// What is under a point in the view, cast from the camera rather than
    /// asked of the renderer: its hit test reads the viewport of its last
    /// frame, and the headless reachability check has never drawn one.
    private func hits(at point: NSPoint, mode: SCNHitTestSearchMode) -> [SCNHitTestResult] {
        guard let ray = ray(through: point) else { return [] }
        return built.scene.rootNode.hitTestWithSegment(
            from: ray.from, to: ray.to, options: [SCNHitTestOption.searchMode.rawValue: mode.rawValue])
    }

    /// The camera's field of view is vertical, so the height is what the
    /// view's height spans and the width follows the aspect.
    private func ray(through point: NSPoint) -> (from: SCNVector3, to: SCNVector3)? {
        let eye = built.pointOfView
        guard bounds.width > 0, bounds.height > 0, let camera = eye.camera else { return nil }
        let halfHeight = tan(camera.fieldOfView / 2 * .pi / 180)
        let halfWidth = halfHeight * bounds.width / bounds.height
        let x = (point.x / bounds.width * 2 - 1) * halfWidth
        let y = (point.y / bounds.height * 2 - 1) * halfHeight
        let direction = eye.simdConvertVector(SIMD3(Float(x), Float(y), -1), to: nil)
        let from = eye.simdWorldPosition
        let to = from + simd_normalize(direction) * Float(camera.zFar)
        return (SCNVector3(from), SCNVector3(to))
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
        pressed = (event.locationInWindow, isOnThePet(point), isTummy(point))
        // The window moves by its background, so the press goes through. It
        // used to wait here for the next event instead, which stalled the run
        // loop until the mouse came up and swallowed that mouse up, so the
        // click count was unreliable and nothing could drive it but a hand.
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        super.mouseUp(with: event)
        guard let pressed else { return }
        let end = event.locationInWindow
        let moved = hypot(end.x - pressed.start.x, end.y - pressed.start.y)
        switch PetClick.decide(onPet: pressed.onPet, onTummy: pressed.onTummy,
                               clicks: event.clickCount, moved: moved) {
        case .poke: onPoke?()
        case .dance: onTummyDoubleClick?()
        case .giggle:
            giggleStartedAt = CACurrentMediaTime()
            quicken(for: Giggle.duration)
            onGiggle?()
        case .nothing: break
        }
    }
}
