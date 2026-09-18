#!/usr/bin/env swift
// Rasterises the brand SVGs into the PNGs the bundle ships, so every pixel in
// the app is reproducible from design/ rather than from a file nobody can redo.
//
// Usage: swift scripts/render-icon.swift <design-dir> <out-dir>

import AppKit

let arguments = CommandLine.arguments
guard arguments.count > 2 else {
    FileHandle.standardError.write(Data("usage: render-icon.swift <design-dir> <out-dir>\n".utf8))
    exit(2)
}
let design = URL(fileURLWithPath: arguments[1])
let out = URL(fileURLWithPath: arguments[2])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

/// An explicit sRGB bitmap at exactly the requested pixel size. Drawing into an
/// NSImage instead picks up the display's backing scale and colour space.
func render(_ svg: URL, size: Int) throws -> Data {
    guard let image = NSImage(contentsOf: svg) else {
        throw NSError(domain: "render-icon", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "could not rasterize \(svg.lastPathComponent)",
        ])
    }
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else {
        throw NSError(domain: "render-icon", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "could not allocate a \(size)px bitmap",
        ])
    }
    bitmap.size = NSSize(width: size, height: size)
    let srgb = bitmap.retagging(with: .sRGB) ?? bitmap
    guard let context = NSGraphicsContext(bitmapImageRep: srgb) else {
        throw NSError(domain: "render-icon", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "could not make a context",
        ])
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size),
               from: .zero, operation: .sourceOver, fraction: 1)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = srgb.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "render-icon", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "could not encode a PNG",
        ])
    }
    return png
}

// The iconset macOS expects, plus the menu bar template at 1x and 2x.
let iconset = out.appendingPathComponent("Squawk.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let icon = design.appendingPathComponent("squawk_app_icon.svg")
for (size, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let pixels = size * scale
    let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
    try render(icon, size: pixels).write(to: iconset.appendingPathComponent(name))
}

let template = design.appendingPathComponent("squawk_menubar_template.svg")
try render(template, size: 18).write(to: out.appendingPathComponent("StatusTemplate.png"))
try render(template, size: 36).write(to: out.appendingPathComponent("StatusTemplate@2x.png"))

print("rendered \(iconset.path) and the status template")
