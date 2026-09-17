#!/usr/bin/env swift
// Generates Calma's app icon with Core Graphics.
//
//   swift Scripts/make-icon.swift
//
// Writes Resources/AppIcon.icns, screenshots/icon-1024.png, site/assets/icon.png and site/assets/favicon.png.

import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

/// Continuous-corner rounded rectangle, close to the macOS app icon shape.
func squircle(in rect: CGRect, radius r: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let k: CGFloat = 1.28 // extends the curve for a smoother, superellipse-like corner
    let minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
    let c = r * k
    path.move(to: CGPoint(x: minX + c, y: minY))
    path.addLine(to: CGPoint(x: maxX - c, y: minY))
    path.addCurve(to: CGPoint(x: maxX, y: minY + c), control1: CGPoint(x: maxX - c * 0.25, y: minY), control2: CGPoint(x: maxX, y: minY + c * 0.25))
    path.addLine(to: CGPoint(x: maxX, y: maxY - c))
    path.addCurve(to: CGPoint(x: maxX - c, y: maxY), control1: CGPoint(x: maxX, y: maxY - c * 0.25), control2: CGPoint(x: maxX - c * 0.25, y: maxY))
    path.addLine(to: CGPoint(x: minX + c, y: maxY))
    path.addCurve(to: CGPoint(x: minX, y: maxY - c), control1: CGPoint(x: minX + c * 0.25, y: maxY), control2: CGPoint(x: minX, y: maxY - c * 0.25))
    path.addLine(to: CGPoint(x: minX, y: minY + c))
    path.addCurve(to: CGPoint(x: minX + c, y: minY), control1: CGPoint(x: minX, y: minY + c * 0.25), control2: CGPoint(x: minX + c * 0.25, y: minY))
    path.closeSubpath()
    return path
}

func drawIcon(size: Int) -> CGImage {
    let s = CGFloat(size)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // Body with a soft drop shadow, inside a ~10% margin like Apple's template.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: body, radius: 150)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x0f3b36, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(color(0x3f968b))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [color(0x6cc3b0), color(0x2f7f78)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Gentle top highlight.
    let highlight = CGGradient(colorsSpace: space, colors: [color(0xffffff, 0.22), color(0xffffff, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(highlight, startCenter: CGPoint(x: 360, y: 900), startRadius: 0,
                           endCenter: CGPoint(x: 360, y: 900), endRadius: 620, options: [])
    ctx.restoreGState()

    // Battery glyph (vertical).
    let batteryRect = CGRect(x: 352, y: 248, width: 320, height: 500)
    let capRect = CGRect(x: 452, y: 748, width: 120, height: 44)
    let white = color(0xffffff)
    let lineWidth: CGFloat = 34

    ctx.setFillColor(white)
    ctx.addPath(CGPath(roundedRect: capRect, cornerWidth: 18, cornerHeight: 18, transform: nil))
    ctx.fillPath()
    // Hide cap's lower rounded corners behind the body stroke.
    ctx.fill(CGRect(x: capRect.minX, y: capRect.minY, width: capRect.width, height: 20))

    ctx.setStrokeColor(white)
    ctx.setLineWidth(lineWidth)
    ctx.addPath(CGPath(roundedRect: batteryRect, cornerWidth: 64, cornerHeight: 64, transform: nil))
    ctx.strokePath()

    // Fill ~80% with a soft wave on top.
    let inset: CGFloat = lineWidth / 2 + 22
    let inner = batteryRect.insetBy(dx: inset, dy: inset)
    let fillTop = inner.minY + inner.height * 0.80
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: inner, cornerWidth: 34, cornerHeight: 34, transform: nil))
    ctx.clip()
    let wave = CGMutablePath()
    wave.move(to: CGPoint(x: inner.minX, y: inner.minY))
    wave.addLine(to: CGPoint(x: inner.minX, y: fillTop))
    let amplitude: CGFloat = 16
    let w = inner.width
    wave.addCurve(to: CGPoint(x: inner.minX + w / 2, y: fillTop),
                  control1: CGPoint(x: inner.minX + w * 0.18, y: fillTop + amplitude * 1.6),
                  control2: CGPoint(x: inner.minX + w * 0.32, y: fillTop + amplitude * 1.6))
    wave.addCurve(to: CGPoint(x: inner.maxX, y: fillTop),
                  control1: CGPoint(x: inner.minX + w * 0.68, y: fillTop - amplitude * 1.6),
                  control2: CGPoint(x: inner.minX + w * 0.82, y: fillTop - amplitude * 1.6))
    wave.addLine(to: CGPoint(x: inner.maxX, y: inner.minY))
    wave.closeSubpath()
    ctx.addPath(wave)
    ctx.setFillColor(color(0xffffff, 0.95))
    ctx.fillPath()
    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: url)
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Calma-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try writePNG(drawIcon(size: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try writePNG(drawIcon(size: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let icns = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }

try writePNG(drawIcon(size: 1024), to: root.appendingPathComponent("screenshots/icon-1024.png"))
try writePNG(drawIcon(size: 512), to: root.appendingPathComponent("site/assets/icon.png"))
try writePNG(drawIcon(size: 64), to: root.appendingPathComponent("site/assets/favicon.png"))
try? FileManager.default.removeItem(at: iconset)
print("Wrote \(icns.path)")
