#!/usr/bin/env swift
// Draws the app icon (a slice of toast with note lines on a warm tile) into AppIcon.appiconset.
// Usage: swift scripts/make-app-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha
    )
}

/// The slice: a rectangle whose top is two overlapping round lobes, like a bread loaf's crown.
func slicePath(in rect: NSRect) -> NSBezierPath {
    let lobe = rect.width * 0.30
    let path = NSBezierPath()
    let bottom = rect.minY, top = rect.maxY
    let left = rect.minX, right = rect.maxX
    let corner = rect.width * 0.10
    path.move(to: NSPoint(x: left + corner, y: bottom))
    path.line(to: NSPoint(x: right - corner, y: bottom))
    path.curve(to: NSPoint(x: right, y: bottom + corner), controlPoint1: NSPoint(x: right - corner * 0.45, y: bottom), controlPoint2: NSPoint(x: right, y: bottom + corner * 0.45))
    path.line(to: NSPoint(x: right, y: top - lobe * 1.2))
    // Right lobe, then the dip in the middle, then the left lobe.
    path.curve(to: NSPoint(x: rect.midX, y: top - lobe * 0.35), controlPoint1: NSPoint(x: right + lobe * 0.55, y: top + lobe * 0.15), controlPoint2: NSPoint(x: rect.midX + lobe * 0.9, y: top + lobe * 0.25))
    path.curve(to: NSPoint(x: left, y: top - lobe * 1.2), controlPoint1: NSPoint(x: rect.midX - lobe * 0.9, y: top + lobe * 0.25), controlPoint2: NSPoint(x: left - lobe * 0.55, y: top + lobe * 0.15))
    path.line(to: NSPoint(x: left, y: bottom + corner))
    path.curve(to: NSPoint(x: left + corner, y: bottom), controlPoint1: NSPoint(x: left, y: bottom + corner * 0.45), controlPoint2: NSPoint(x: left + corner * 0.45, y: bottom))
    path.close()
    return path
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = size / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    // macOS icon grid: an 824 pt tile centered in 1024 with a soft drop shadow.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0xF08A2C).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0xFFC163), color(0xF2792B)])!.draw(in: tilePath, angle: -90)

    // The slice, with a crust rim and a lighter crumb inside.
    let sliceRect = NSRect(x: 262, y: 220, width: 500, height: 470)
    let crust = slicePath(in: sliceRect)
    NSGraphicsContext.saveGraphicsState()
    let sliceShadow = NSShadow()
    sliceShadow.shadowColor = color(0x7A3410, 0.35)
    sliceShadow.shadowBlurRadius = 24
    sliceShadow.shadowOffset = NSSize(width: 0, height: -10)
    sliceShadow.set()
    color(0xB65E1E).setFill()
    crust.fill()
    NSGraphicsContext.restoreGraphicsState()
    let crumb = slicePath(in: sliceRect.insetBy(dx: 34, dy: 34))
    NSGradient(colors: [color(0xFFF4DC), color(0xFBDDA4)])!.draw(in: crumb, angle: -90)

    // Note lines on the crumb.
    color(0xC9772F, 0.85).setFill()
    let lineX = sliceRect.minX + 98
    for (index, width) in [300.0, 300.0, 190.0].enumerated() {
        let y = sliceRect.minY + 268 - CGFloat(index) * 72
        NSBezierPath(roundedRect: NSRect(x: lineX, y: y, width: width, height: 30), xRadius: 15, yRadius: 15).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [String] = []
for (points, scale) in sizes {
    let pixels = points * scale
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    let data = drawIcon(size: CGFloat(pixels)).representation(using: .png, properties: [:])!
    try data.write(to: output.appendingPathComponent(name))
    images.append(#"    { "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(points)x\#(points)", "filename" : "\#(name)" }"#)
}
let contents = "{\n  \"images\" : [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try contents.write(to: output.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(sizes.count) icons to \(output.path)")
