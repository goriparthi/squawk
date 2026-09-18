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
    let walking = CommandLine.arguments.contains("--dog")
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

    let moods: [FaceExpression] = [.calm, .happy, .urgent, .curious, .cross, .dizzy]
    for step in 0..<frames {
        let phase = Double(step) / Double(frames)
        if showingCast {
            // A new rig per character: the colours and the shape are built into
            // the model, and a dog is a different model entirely.
            let persona = Cast.all[step]
            let cell = Rigs.make(for: persona)
            cell.apply(persona.build == .quadruped
                       ? Trot.standing() : BodyPose.pose(for: .calm).pose3D())
            let eye = FaceTint(persona.eye.red, persona.eye.green, persona.eye.blue)
            cell.paintFace(FaceArtist(frame: FaceFrame.target(for: .calm, resting: eye)))
            renderer.scene = cell.scene
            renderer.pointOfView = cell.pointOfView
        } else if walking {
            let persona = Cast.all.first { $0.build == .quadruped } ?? Cast.default
            let cell = Rigs.make(for: persona)
            cell.apply(Trot.pose(phase: phase))
            let eye = FaceTint(persona.eye.red, persona.eye.green, persona.eye.blue)
            cell.paintFace(FaceArtist(frame: FaceFrame.target(for: .calm, resting: eye)))
            renderer.scene = cell.scene
            renderer.pointOfView = cell.pointOfView
        } else if dancing {
            // One frame per move, taken mid move so the pose is at full throw.
            let moment = Double(step) * Dance.moveLength + Dance.moveLength * 0.55
            built.apply(Dance.pose(at: moment))
            built.tint(hue: Dance.frame(at: moment).hue)
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

if CommandLine.arguments.contains("--check-hits") {
    let missed = SpeechScene.unreachableControls()
    guard missed.isEmpty else {
        for miss in missed {
            FileHandle.standardError.write(Data(
                "unreachable: \(miss.control) at head \(Int(miss.head)); the click landed on \(miss.landedOn)\n".utf8))
        }
        exit(1)
    }
    print("every showing control is reachable at \(SpeechScene.heads.map { Int($0) })")
    exit(0)
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
