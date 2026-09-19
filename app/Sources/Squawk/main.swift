import AppKit
import Metal
import SceneKit
import ServiceManagement
import SquawkCore

// Recovery without the GUI. Open at Login can be registered against whatever
// copy was running at the time, including a build directory, and the only way
// back was a menu click in that same copy.
// Does pane focus work for the terminal I am actually in? Asks each terminal
// Squawk knows in turn, which also makes macOS raise that terminal's Automation
// consent for Squawk rather than for whatever shell ran this.
if let index = CommandLine.arguments.firstIndex(of: "--focus-tty"),
   index + 1 < CommandLine.arguments.count {
    let tty = CommandLine.arguments[index + 1]
    let cwd = FileManager.default.currentDirectoryPath
    var focused = false
    for terminal in PaneFocus.Terminal.allCases {
        guard let source = PaneFocus.script(for: terminal, tty: tty, cwd: cwd),
              let script = NSAppleScript(source: source) else {
            print("\(terminal.applicationName): no script for this input")
            continue
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int).map(String.init) ?? "?"
            print("\(terminal.applicationName): error \(code)")
            continue
        }
        let answer = result.stringValue ?? "no result"
        print("\(terminal.applicationName): \(answer)")
        if answer == "focused" { focused = true }
    }
    exit(focused ? 0 : 1)
}

// A contact sheet of every expression, for tuning them against each other
// rather than one at a time on a live dial.
if let index = CommandLine.arguments.firstIndex(of: "--preview-faces"),
   index + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[index + 1]
    let cell = 150
    let cases = FaceExpression.allCases
    let columns = 5  // fourteen faces, three rows
    let rows = (cases.count + columns - 1) / columns
    let width = cell * columns
    let height = cell * rows + 26 * rows

    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    Palette.faceBottom.withAlphaComponent(1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    for (offset, face) in cases.enumerated() {
        let column = offset % columns
        let row = offset / columns
        let originY = height - (row + 1) * (cell + 26)
        // Drawn straight into the sheet on the real face colour. A cached rep
        // comes back opaque, which hid every glow behind a white square.
        let frame = NSRect(x: column * cell, y: originY + 26, width: cell, height: cell)
        let view = FaceView()
        view.setFrameSize(NSSize(width: cell, height: cell))
        view.expression = face
        view.settle()
        NSGraphicsContext.saveGraphicsState()
        let shift = NSAffineTransform()
        shift.translateX(by: frame.minX, yBy: frame.minY)
        shift.concat()
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        let label = NSAttributedString(string: face.rawValue, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.62, alpha: 1),
        ])
        label.draw(at: NSPoint(x: CGFloat(column * cell) + (CGFloat(cell) - label.size().width) / 2,
                               y: CGFloat(originY) + 6))
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try? bitmap.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
    exit(0)
}

// Downloads and verifies a release without swapping anything, so the risky
// half of an update can be exercised on its own.
if let index = CommandLine.arguments.firstIndex(of: "--stage-update"),
   index + 1 < CommandLine.arguments.count,
   let url = URL(string: CommandLine.arguments[index + 1]) {
    let started = Date()
    Installer.stage(dmg: url) { staged in
        let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
        switch staged {
        case .ready:
            print("staged and verified in \(elapsed)s")
            exit(0)
        case .failed(let message):
            FileHandle.standardError.write(Data("failed after \(elapsed)s: \(message)\n".utf8))
            exit(1)
        }
    }
    // Staging finishes on a background queue; the run loop keeps this alive.
    RunLoop.main.run(until: Date().addingTimeInterval(180))
    FileHandle.standardError.write(Data("timed out\n".utf8))
    exit(1)
}

// Renders the companion with its speech bubble filled, at the sizes the slider
// reaches, so the card's width can be judged without a screenshot of the desktop.
if let index = CommandLine.arguments.firstIndex(of: "--preview-speech"),
   index + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[index + 1]
    var cells = SpeechScene.heads.flatMap { head in
        SpeechScene.samples.map { (head, $0, nil as String?) }
    }
    cells.append((300, SpeechScene.samples[0], Fortune.all[0]))
    // The longest thing wellness ever says, to prove it fits the bubble.
    cells.append((300, SpeechScene.samples[0],
                  WellnessPrompt.allCases.max { $0.message.count < $1.message.count }?.message))
    let widest = cells.map { BodyGeometry.canvas(head: $0.0).width }.max() ?? 300
    let tallest = cells.map { BodyGeometry.canvas(head: $0.0).height }.max() ?? 300
    let width = Int(widest) * cells.count
    let height = Int(tallest)

    let sheet = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    sheet.size = NSSize(width: width, height: height)
    let sheetContext = NSGraphicsContext(bitmapImageRep: sheet)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = sheetContext
    NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    NSGraphicsContext.restoreGraphicsState()

    for (offset, cell) in cells.enumerated() {
        let view = SpeechScene.build(head: cell.0, request: cell.1, fortune: cell.2).root
        // cacheDisplay draws the buttons and labels too; draw(_:) would only
        // give the background, which is the half that was never in doubt.
        guard let shot = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
        view.cacheDisplay(in: view.bounds, to: shot)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = sheetContext
        let origin = NSPoint(x: CGFloat(offset) * widest + (widest - view.bounds.width) / 2,
                             y: CGFloat(height) - view.bounds.height)
        shot.draw(in: NSRect(origin: origin, size: view.bounds.size))
        NSGraphicsContext.restoreGraphicsState()
    }
    sheetContext.flushGraphics()
    try? sheet.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
    exit(0)
}

// Proves every button that is showing can actually be clicked. A control the
// background's hit test rejects looks exactly like a live one on screen.
// Renders the modelled companion offscreen, so its shapes and lighting can be
// judged without putting a window on the user's screen.
if let index = CommandLine.arguments.firstIndex(of: "--preview-3d"),
   index + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[index + 1]
    // One cell per character when showing the cast, otherwise one pet through
    // its walk or its routine.
    let showingCast = CommandLine.arguments.contains("--cast")
    let built = CompanionScene(persona: Cast.default)
    guard let device = MTLCreateSystemDefaultDevice() else {
        FileHandle.standardError.write(Data("no metal device\n".utf8))
        exit(1)
    }
    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = built.scene
    renderer.pointOfView = built.pointOfView
    renderer.autoenablesDefaultLighting = false

    // Two strips: a stride and a dance, each judged as a sequence rather than
    // as one pose, because that is the only way a cycle can be judged at all.
    let dancing = CommandLine.arguments.contains("--dance")
    let frames = showingCast ? Cast.all.count : (dancing ? Dance.Move.allCases.count : 6)
    // The proportions the companion actually gets in the panel: the window's
    // width by everything below the bubble.
    let cell = CGSize(width: 360, height: 392)
    let sheet = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(cell.width) * frames, pixelsHigh: Int(cell.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    sheet.size = NSSize(width: Int(cell.width) * frames, height: Int(cell.height))
    let context = NSGraphicsContext(bitmapImageRep: sheet)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: sheet.size.width, height: sheet.size.height).fill()
    NSGraphicsContext.restoreGraphicsState()

    let moods: [FaceExpression] = [.calm, .happy, .grooving, .curious, .cross, .dizzy]
    for step in 0..<frames {
        let phase = Double(step) / Double(frames)
        if showingCast {
            // A new rig per character: the colours and the shape are built into
            // the model, and a dog is a different model entirely.
            let persona = Cast.all[step]
            let cell = CompanionScene(persona: persona)
            cell.apply(BodyPose.pose(for: .calm).pose3D())
            let eye = FaceTint(persona.eye.red, persona.eye.green, persona.eye.blue)
            cell.paintFace(FaceArtist(frame: FaceFrame.target(for: .calm, resting: eye)))
            renderer.scene = cell.scene
            renderer.pointOfView = cell.pointOfView
        } else if dancing {
            // One frame per move, taken mid move so the pose is at full throw.
            let moment = Double(step) * Dance.moveLength + Dance.moveLength * 0.55
            built.apply(Dance.pose(at: moment))
            built.tint(hue: Dance.frame(at: moment).hue)
        } else if step == frames - 1 {
            // The last cell is the refusal, which is a pose rather than a walk.
            built.apply(BodyPose.pose(for: .dizzy).pose3D())
        } else {
            built.apply(Gait.pose(phase: phase))
        }
        built.paintFace(FaceArtist(frame: FaceFrame.target(for: moods[step % moods.count])))
        let shot = renderer.snapshot(atTime: 0, with: cell, antialiasingMode: .multisampling4X)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        shot.draw(in: NSRect(x: CGFloat(step) * cell.width, y: 0,
                             width: cell.width, height: cell.height))
        NSGraphicsContext.restoreGraphicsState()
    }
    context.flushGraphics()
    try? sheet.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
    exit(0)
}

// Prints the numbers the window is built from, because a panel that comes out
// the wrong size is otherwise a guessing game against a running process.
if CommandLine.arguments.contains("--dump-geometry") {
    let config = ConfigFile.load()
    let head = config.clampedDiameter
    let canvas = BodyGeometry.canvas(head: head)
    print("style=\(config.style.rawValue) head=\(head)")
    print("bubbleFloor=\(DialGeometry.bubbleFloor) bubbleHeight=\(BodyGeometry.bubbleHeight(head: head))")
    print("bubbleWidth=\(DialGeometry.bubbleWidth()) canvas=\(canvas.width)x\(canvas.height)")
    exit(0)
}

// Proves the audio tap actually runs, which needs the user's consent and so
// cannot be checked any other way than by asking for it.
if CommandLine.arguments.contains("--test-audio") {
    let listener = SystemAudio()
    listener.diagnostics = true
    if let trouble = listener.start() {
        FileHandle.standardError.write(Data("\(trouble.message)\n".utf8))
        exit(1)
    }
    var heard = 0
    var loudest = 0.0
    listener.onSpectrum = { spectrum in
        heard += 1
        loudest = max(loudest, spectrum.level)
        if heard % 20 == 0 {
            let bars = spectrum.bands.map { String(format: "%.2f", $0) }.joined(separator: " ")
            print("level \(String(format: "%.3f", spectrum.level))  bands \(bars)")
        }
    }
    RunLoop.main.run(until: Date().addingTimeInterval(6))
    listener.stop()
    print("blocks: \(heard), loudest: \(String(format: "%.3f", loudest))")
    exit(heard > 0 ? 0 : 2)
}

// Renders the pet reacting to a beat, offscreen, so the music behaviour can be
// judged without needing the tap to be working on this machine.
if let index = CommandLine.arguments.firstIndex(of: "--preview-music"),
   index + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[index + 1]
    let built = CompanionScene(persona: Cast.default)
    built.headphones.isHidden = false
    guard let device = MTLCreateSystemDefaultDevice() else { exit(1) }
    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = built.scene
    renderer.pointOfView = built.pointOfView
    renderer.autoenablesDefaultLighting = false

    let frames = 5
    let cell = CGSize(width: 360, height: 392)
    let sheet = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(cell.width) * frames, pixelsHigh: Int(cell.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    sheet.size = NSSize(width: Int(cell.width) * frames, height: Int(cell.height))
    let context = NSGraphicsContext(bitmapImageRep: sheet)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: sheet.size.width, height: sheet.size.height).fill()
    NSGraphicsContext.restoreGraphicsState()

    for step in 0..<frames {
        // One moment of a beat each, from the hit to the recovery.
        let sinceBeat = Double(step) * 0.09
        let pulse = BeatDetector.pulse(since: sinceBeat)
        var pose = BodyPose.pose(for: .grooving).pose3D()
        pose.bob -= pulse * 0.03
        pose.headPitch += pulse * 7
        pose.leftKnee += pulse * 7
        pose.rightKnee += pulse * 7
        pose.leftShoulder += pulse * 9
        pose.rightShoulder += pulse * 9
        built.apply(pose)

        let bands = (0..<Spectrum.bandCount).map { band in
            min(1, 0.25 + pulse * 0.8 - Double(band) * 0.09)
        }
        built.show(Spectrum(bands: bands, level: 0.6))
        built.light(step == frames - 1
                    ? PrivacyState(microphone: true)
                    : (step == frames - 2 ? PrivacyState(camera: true) : .clear))
        built.paintFace(FaceArtist(frame: FaceFrame.target(for: .grooving)))

        let shot = renderer.snapshot(atTime: 0, with: cell, antialiasingMode: .multisampling4X)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        shot.draw(in: NSRect(x: CGFloat(step) * cell.width, y: 0,
                             width: cell.width, height: cell.height))
        NSGraphicsContext.restoreGraphicsState()
    }
    context.flushGraphics()
    try? sheet.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
    exit(0)
}

// Reports what the machine is using right now. Opens nothing: it is the same
// two questions the system's own dots answer, asked of the same frameworks.
if CommandLine.arguments.contains("--test-privacy") {
    let watch = PrivacyWatch()
    watch.onChange = { state in
        print("microphone=\(state.microphone) camera=\(state.camera) light=\(state.light.map(String.init(describing:)) ?? "none")")
    }
    for line in PrivacyWatch.describeProcesses() { print(line) }
    watch.start()
    print("watching for 6 seconds; start a recording or a call to see it change")
    RunLoop.main.run(until: Date().addingTimeInterval(6))
    let state = watch.state
    print("final: microphone=\(state.microphone) camera=\(state.camera)")
    watch.stop()
    exit(0)
}

// Runs the tap into the beat detector and writes what it found to a file.
// Launched with `open`, which is the only way the tap is granted audio, so
// there is nowhere for stdout to go.
if let index = CommandLine.arguments.firstIndex(of: "--test-beat"),
   index + 1 < CommandLine.arguments.count {
    let out = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    let seconds = CommandLine.arguments.count > index + 2
        ? Double(CommandLine.arguments[index + 2]) ?? 16 : 16
    let listener = SystemAudio()
    var detector = BeatDetector()
    var lines: [String] = []
    var beats: [TimeInterval] = []
    var blocks = 0
    var loudest = 0.0
    let started = CACurrentMediaTime()

    listener.onSpectrum = { spectrum in
        blocks += 1
        loudest = max(loudest, spectrum.level)
        let now = CACurrentMediaTime()
        if detector.track(spectrum, at: now) {
            beats.append(now - started)
            lines.append(String(format: "beat at %.3f  tempo %@  low %.3f",
                                now - started,
                                detector.tempo.map { String(format: "%.3f/s", $0) } ?? "-",
                                spectrum.bands.first ?? 0))
        }
    }
    if let trouble = listener.start() {
        try? "start failed: \(trouble.message)\n".write(to: out, atomically: true,
                                                        encoding: .utf8)
        exit(1)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    listener.stop()

    var report = lines
    report.append("blocks \(blocks), loudest \(String(format: "%.3f", loudest))")
    report.append("beats \(beats.count)")
    if beats.count > 2 {
        let gaps = zip(beats.dropFirst(), beats).map(-)
        let sorted = gaps.sorted()
        let median = sorted[sorted.count / 2]
        report.append(String(format: "median gap %.4fs = %.1f bpm", median, 60 / median))
        report.append(String(format: "spread %.4fs", (sorted.last ?? 0) - (sorted.first ?? 0)))
    }
    report.append("final tempo \(detector.tempo.map { String(format: "%.3f/s = %.1f bpm", $0, $0 * 60) } ?? "none")")
    try? report.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
    exit(0)
}

// One clean render of the companion for the landing page, transparent and at
// twice the size it is shown at, so the site ships the real thing rather than
// an illustration of it that will drift.
if let index = CommandLine.arguments.firstIndex(of: "--preview-hero"),
   index + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[index + 1]
    let persona = Cast.named(CommandLine.arguments.count > index + 2
                             ? CommandLine.arguments[index + 2] : nil)
    let built = CompanionScene(persona: persona)
    // Worn, so the hero shows the tallest the pet ever is and any clipping at
    // the top of the frame shows up here rather than on someone's desktop.
    built.headphones.isHidden = !CommandLine.arguments.contains("--worn")
    built.apply(BodyPose.pose(for: .calm).pose3D())
    let eye = FaceTint(persona.eye.red, persona.eye.green, persona.eye.blue)
    built.paintFace(FaceArtist(frame: FaceFrame.target(for: .calm, resting: eye)))
    guard let device = MTLCreateSystemDefaultDevice() else { exit(1) }
    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = built.scene
    renderer.pointOfView = built.pointOfView
    renderer.autoenablesDefaultLighting = false
    let shot = renderer.snapshot(atTime: 0, with: CGSize(width: 720, height: 784),
                                 antialiasingMode: .multisampling4X)
    guard let data = shot.tiffRepresentation,
          let rep = NSBitmapImageRep(data: data),
          let png = rep.representation(using: .png, properties: [:])
    else { exit(1) }
    try? png.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
    exit(0)
}

// Reports what each supported player says, which is the only way to tell a
// missing permission from a player nobody is using.
if CommandLine.arguments.contains("--test-nowplaying") {
    for line in NowPlaying.diagnose() { print(line) }
    if let track = NowPlaying.current() {
        print("current: \(track.title) by \(track.artist) via \(track.source)")
    } else {
        print("current: nothing readable")
    }
    let maker = NowPlaying.playingApplication()
    print("making sound: \(maker?.localizedName ?? "nothing with a name")")
    if let maker, let tab = NowPlaying.browserTab(for: maker) { print("front tab: \(tab)") }
    for app in PrivacyWatch.applicationsPlaying() {
        print("  \(app.localizedName ?? "pid \(app.processIdentifier)")")
    }
    exit(0)
}

if CommandLine.arguments.contains("--check-hits") {
    if let trouble = SpeechScene.petIsReachable() {
        FileHandle.standardError.write(Data("unreachable: \(trouble)\n".utf8))
        exit(1)
    }
    if let trouble = SpeechScene.clicksAreUnderstood() {
        FileHandle.standardError.write(Data("misread: \(trouble)\n".utf8))
        exit(1)
    }
    let missed = SpeechScene.unreachableControls()
    guard missed.isEmpty else {
        for miss in missed {
            FileHandle.standardError.write(Data(
                "unreachable: \(miss.control) at head \(Int(miss.head)); the click landed on \(miss.landedOn)\n".utf8))
        }
        exit(1)
    }
    print("every showing control is reachable at \(SpeechScene.heads.map { Int($0) })")
    print("a tap on the head pokes, a tap on the tummy giggles, a double tap dances, a drag does nothing")
    exit(0)
}

// Runs the real pose loop headless: `--simulate <fps> <seconds> <face> <out.png>`.
// Prints every joint afterwards, so a joint that has run away or gone NaN
// (a foot that vanishes) can be caught without watching the live pet.
if let index = CommandLine.arguments.firstIndex(of: "--simulate"),
   index + 4 < CommandLine.arguments.count,
   let fps = Double(CommandLine.arguments[index + 1]),
   let seconds = Double(CommandLine.arguments[index + 2]),
   let face = FaceExpression(rawValue: CommandLine.arguments[index + 3]) {
    let out = CommandLine.arguments[index + 4]
    let view = CompanionView(face: FaceAnimator())
    view.frame = NSRect(x: 0, y: 0, width: 360, height: 392)
    view.pose = BodyPose.pose(for: face)
    view.stand()
    var clock = 1000.0
    var worst: [String: Double] = [:]
    // What the live pet goes through: a walk on, a routine, a track.
    let arriving = CommandLine.arguments.contains("--arrive")
    let dancing = CommandLine.arguments.contains("--dance")
    let music = CommandLine.arguments.contains("--music")
    // Drives the mouth as if something were being said, so the jaw can be
    // judged offscreen rather than by talking to the live pet.
    if CommandLine.arguments.contains("--lamp") {
        view.light(PrivacyState(microphone: true))
    }
    if let index = CommandLine.arguments.firstIndex(of: "--listening"),
       index + 1 < CommandLine.arguments.count,
       let level = Double(CommandLine.arguments[index + 1]) {
        view.listening = level
    }
    if let talk = CommandLine.arguments.firstIndex(of: "--talking") {
        // A number after it pins the jaw open that far, for judging the range.
        let fixed = talk + 1 < CommandLine.arguments.count
            ? Double(CommandLine.arguments[talk + 1]) : nil
        view.speechLevel = { fixed ?? 0.55 + 0.45 * sin(CACurrentMediaTime() * 15.3) }
    }
    let loud = Spectrum(bands: [0.8, 0.7, 0.5, 0.4, 0.3], energy: [0.8, 0.7, 0.5, 0.4, 0.3], level: 0.6)
    if arriving { view.arrive(from: -3, at: clock) }
    if dancing { view.toggleDance(at: clock) }
    let total = Int(fps * seconds)
    for frame in 0..<total {
        clock += 1 / fps
        if music { view.hear(frame % 8 == 0 ? loud : Spectrum(bands: [0.3, 0.2, 0.2, 0.1, 0.1], energy: [0.3, 0.2, 0.2, 0.1, 0.1], level: 0.3)) }
        if dancing, frame == total / 2 { view.toggleDance(at: clock) }
        view.advance(to: clock)
        for (name, angle) in view.jointReport where !angle.isFinite || abs(angle) > abs(worst[name] ?? 0) {
            worst[name] = angle
        }
    }
    for (name, angle) in view.jointReport {
        print("\(name): now \(String(format: "%.2f", angle)) worst \(String(format: "%.2f", worst[name] ?? 0))\(angle.isFinite ? "" : "  NOT FINITE")")
    }
    guard let device = MTLCreateSystemDefaultDevice() else { exit(1) }
    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = view.scene
    renderer.pointOfView = view.scene.rootNode.childNodes.first { $0.camera != nil }
    let shot = renderer.snapshot(atTime: 0, with: CGSize(width: 360, height: 392),
                                 antialiasingMode: .multisampling4X)
    if let tiff = shot.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    }
    exit(0)
}

// What the pet would say, and what it would say it with. `--say` speaks;
// with no text it reads the live roster, which is empty from a terminal.
if let index = CommandLine.arguments.firstIndex(of: "--say"),
   index + 1 < CommandLine.arguments.count {
    // `--voice piper:en_US-amy-low` tries one without changing the setting.
    let override = CommandLine.arguments.firstIndex(of: "--voice")
        .flatMap { $0 + 1 < CommandLine.arguments.count ? CommandLine.arguments[$0 + 1] : nil }
    let speaker = Speaker(choice: .restored(override ?? Settings.voiceId))
    print("speaking with: \(speaker.title)")
    speaker.say(CommandLine.arguments[index + 1])
    // Waits for it to finish rather than for a fixed spell: the engine takes
    // about a second to load a model before there is any sound at all.
    let deadline = Date().addingTimeInterval(40)
    var started = false
    while Date() < deadline {
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        if speaker.isSpeaking { started = true } else if started { break }
    }
    exit(0)
}

// Both phrasings of the same briefing, side by side, so the model's version
// can be judged against the plain one without waiting for a request to arrive.
if CommandLine.arguments.contains("--test-phrasing") {
    let briefing = Briefing(items: [
        Briefing.Item(project: "squawk", tool: "Bash", summary: "git push --force",
                      risky: true, awaitsDecision: true, waited: 40),
        Briefing.Item(project: "collect_db", tool: "Edit", summary: "update schema.sql",
                      risky: false, awaitsDecision: true, waited: 5),
    ])
    print("plain:  \(Utterance.spoken(briefing))")
    let configured = Settings.phrasingModel
    Ollama.local { models in
        guard let model = Ollama.choose(from: models, configured: configured) else {
            print("model:  none usable on this machine; pull \(Ollama.suggested)")
            print("installed: \(models.isEmpty ? "nothing local" : models.joined(separator: ", "))")
            exit(0)
        }
        print("model:  \(model)")
        let started = Date()
        Ollama.phrase(briefing, model: model) { phrased in
            let took = Int(Date().timeIntervalSince(started) * 1000)
            print("said:   \(phrased ?? "(refused or timed out, the plain one is used)")")
            print("took:   \(took) ms of \(Int(Ollama.deadline * 1000)) allowed")
            exit(0)
        }
    }
    RunLoop.main.run(until: Date().addingTimeInterval(20))
    print("model:  no answer in time; the plain one is used")
    exit(0)
}

// Listens and writes down what it heard and what it would do about it. From
// the bundle only: a terminal launch is refused the microphone in silence.
@MainActor
final class EarsLog {
    let path: String
    var lines: [String] = []
    init(path: String) { self.path = path }
    func add(_ line: String) {
        lines.append(line)
        try? lines.joined(separator: "\n").appending("\n")
            .write(toFile: path, atomically: true, encoding: .utf8)
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--test-ears"),
   index + 1 < CommandLine.arguments.count {
    let seconds = index + 2 < CommandLine.arguments.count
        ? Double(CommandLine.arguments[index + 2]) ?? 20 : 20
    let log = EarsLog(path: CommandLine.arguments[index + 1])
    log.add("permitted: \(Ears.isPermitted)")
    let ears = Ears()
    let wake = Listening.wakeWords(persona: Settings.persona.name)
    ears.onHeard = { transcript, final in
        let after = Listening.afterWake(transcript, wakeWords: wake)
        let intent = Listening.heard(after ?? transcript)
        log.add("heard: \(transcript) | final: \(final) | afterWake: \(after ?? "-") | intent: \(intent)")
    }
    Ears.requestConsent { granted in
        Task { @MainActor in
            log.add("consent: \(granted)")
            if let trouble = ears.start(continuous: true) { log.add("trouble: \(trouble.message)") }
        }
    }
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    log.add("stopped")
    exit(0)
}

// Does it still speak while the microphone is open? Spoken replies were
// arriving at the synthesiser and never coming out of the speakers.
if CommandLine.arguments.contains("--test-speak-listening") {
    let speaker = Speaker(choice: .restored(Settings.voiceId))
    let ears = Ears()
    Ears.requestConsent { granted in
        Task { @MainActor in
            print("consent: \(granted)")
            let trouble = ears.start(continuous: true)
            print("ears running: \(ears.isRunning) trouble: \(trouble?.message ?? "none")")
            speaker.say("Testing one two three, can you hear this.")
            print("asked to speak; isSpeaking now: \(speaker.isSpeaking)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                print("after 1.5s, isSpeaking: \(speaker.isSpeaking)")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                print("after 6s, isSpeaking: \(speaker.isSpeaking)")
                ears.stop()
                print("ears stopped; speaking again with the microphone shut")
                speaker.say("And now with the microphone closed.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    print("after shutting the mic, isSpeaking: \(speaker.isSpeaking)")
                }
            }
        }
    }
    RunLoop.main.run(until: Date().addingTimeInterval(16))
    exit(0)
}

// The same answering path a spoken question takes, without the microphone.
if let index = CommandLine.arguments.firstIndex(of: "--ask"),
   index + 1 < CommandLine.arguments.count {
    let question = CommandLine.arguments[index + 1]
    let asking = Asking()
    let configured = Settings.phrasingModel
    let place = Settings.weatherPlace.isEmpty ? nil : Settings.weatherPlace
    let started = Date()
    Ollama.local { models in
        Task { @MainActor in
            let model = Ollama.choose(from: models, configured: configured)
            print("question: \(question)")
            print("model:    \(model ?? "none; local answers only")")
            asking.answer(question, model: model, place: place) { spoken in
                print("answer:   \(spoken)")
                print("took:     \(Int(Date().timeIntervalSince(started) * 1000)) ms")
                exit(0)
            }
        }
    }
    RunLoop.main.run(until: Date().addingTimeInterval(25))
    print("answer:   (nothing came back in time)")
    exit(1)
}

if CommandLine.arguments.contains("--voice-status") {
    print("engine build for this Mac: \(VoicePack.engine == nil ? "none" : "available")")
    print("engine installed: \(VoicePack.engineIsReady)")
    print("chosen voice: \(Speaker(choice: .restored(Settings.voiceId)).title)")
    for voice in VoicePack.catalog {
        let state = VoicePack.isReady(voice)
            ? "installed"
            : "not installed (\(VoicePack.describe(bytes: VoicePack.downloadBytes(for: voice))) to fetch)"
        print("  \(voice.id): \(state)")
    }
    print("system voices: \(SystemVoice.english().filter { $0.quality != .default }.map(\.name).joined(separator: ", "))")
    exit(0)
}

// The real download, verify and unpack, without a menu.
if let index = CommandLine.arguments.firstIndex(of: "--install-voice"),
   index + 1 < CommandLine.arguments.count,
   let voice = VoicePack.voice(id: CommandLine.arguments[index + 1]) {
    print("installing \(voice.title): \(VoicePack.describe(bytes: VoicePack.downloadBytes(for: voice)))")
    VoicePack.install(voice, progress: { fraction in
        if Int(fraction * 100) % 10 == 0 { print("  \(Int(fraction * 100))%") }
    }, finished: { trouble in
        if let trouble {
            FileHandle.standardError.write(Data("failed: \(trouble.message)\n".utf8))
            exit(1)
        }
        print("installed \(voice.id)")
        exit(0)
    })
    RunLoop.main.run(until: Date().addingTimeInterval(600))
    FileHandle.standardError.write(Data("timed out\n".utf8))
    exit(1)
}

if CommandLine.arguments.contains("--login-status") {
    let status = SMAppService.mainApp.status
    print("status=\(status.rawValue) enabled=\(status == .enabled)")
    exit(0)
}

if CommandLine.arguments.contains("--enable-open-at-login") {
    do {
        try SMAppService.mainApp.register()
        print("register() returned; status=\(SMAppService.mainApp.status.rawValue)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("register failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

if CommandLine.arguments.contains("--disable-open-at-login") {
    do {
        if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
        print("Open at Login is off for \(Bundle.main.bundleURL.path)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("Could not unregister: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
