#!/usr/bin/swift

import AppKit
import Foundation

private let canvasPixels = 1_024
private let artworkPixels = 824
private let insetPixels = (canvasPixels - artworkPixels) / 2

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("app-icon: \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else {
    fail("usage: generate-app-icon-canvas.swift SOURCE.png OUTPUT.png")
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = NSImage(contentsOf: sourceURL) else {
    fail("could not read \(sourceURL.path)")
}

guard source.size.width == source.size.height, source.size.width > 0 else {
    fail("source must be a non-empty square image")
}

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasPixels,
    pixelsHigh: canvasPixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fail("could not allocate the icon canvas")
}

bitmap.size = NSSize(width: canvasPixels, height: canvasPixels)

guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fail("could not create the icon drawing context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
graphicsContext.cgContext.clear(
    CGRect(x: 0, y: 0, width: canvasPixels, height: canvasPixels)
)
graphicsContext.imageInterpolation = .high
source.draw(
    in: NSRect(
        x: insetPixels,
        y: insetPixels,
        width: artworkPixels,
        height: artworkPixels
    ),
    from: NSRect(origin: .zero, size: source.size),
    operation: .sourceOver,
    fraction: 1
)
graphicsContext.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fail("could not encode the padded icon")
}

do {
    try png.write(to: outputURL, options: .atomic)
} catch {
    fail("could not write \(outputURL.path): \(error.localizedDescription)")
}

print(
    "app-icon: centered \(artworkPixels) px artwork on a transparent \(canvasPixels) px canvas"
)
