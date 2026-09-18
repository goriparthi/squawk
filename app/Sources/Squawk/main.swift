import AppKit
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
        let view = FaceView(frame: NSRect(x: 0, y: 0, width: cell, height: cell))
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

// Renders the companion offscreen on a neutral field, so its shapes can be
// judged without photographing whatever is behind the real window.
if let index = CommandLine.arguments.firstIndex(of: "--preview-body"),
   index + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[index + 1]
    let head: CGFloat = 300
    let canvas = BodyGeometry.canvas(head: head)
    let poses: [FaceExpression] = [.calm, .urgent, .happy, .cross, .sad, .restless]
    let cell = NSSize(width: canvas.width, height: canvas.height - BodyGeometry.bubbleHeight(head: head))
    let width = Int(cell.width) * poses.count
    let height = Int(cell.height) + 34

    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.shouldAntialias = true
    context.imageInterpolation = .high
    NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    for (offset, face) in poses.enumerated() {
        let view = CircleBackgroundView(frame: NSRect(origin: .zero, size: cell))
        view.showsBody = true
        view.headDiameter = head
        view.pose = BodyPose.pose(for: face)
        NSGraphicsContext.saveGraphicsState()
        let shift = NSAffineTransform()
        shift.translateX(by: CGFloat(offset) * cell.width, yBy: 34)
        shift.concat()
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()

        let label = NSAttributedString(string: face.rawValue, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.62, alpha: 1),
        ])
        label.draw(at: NSPoint(x: CGFloat(offset) * cell.width + (cell.width - label.size().width) / 2, y: 9))
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try? bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
    exit(0)
}

// Renders the companion with its speech bubble filled, at the sizes the slider
// reaches, so the card's width can be judged without a screenshot of the desktop.
if let index = CommandLine.arguments.firstIndex(of: "--preview-speech"),
   index + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[index + 1]
    let cells = SpeechScene.heads.flatMap { head in SpeechScene.samples.map { (head, $0) } }
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
        let view = SpeechScene.build(head: cell.0, request: cell.1).root
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
