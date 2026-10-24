#!/usr/bin/env swift
// Generates the original Sheafnote app icon: a fanned sheaf of paper tied with a band, with a pen stroke.
// Usage: swift scripts/make-icon.swift   (writes into App/Resources/Assets.xcassets)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appending(path: "App/Resources/Assets.xcassets")
let iconSet = catalog.appending(path: "AppIcon.appiconset")
let accentSet = catalog.appending(path: "AccentColor.colorset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: accentSet, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
// Top-left origin.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

// Background: deep teal gradient.
let gradient = CGGradient(colorsSpace: cs, colors: [color(0x0A4A52), color(0x15838A)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: CGFloat(size)), options: [])

func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// Fanned sheets pivoting about the bottom centre.
let pivot = CGPoint(x: 512, y: 900)
let sheets: [(angle: CGFloat, fill: UInt32)] = [(-11, 0xE3DCC4), (11, 0xEFE9D6), (0, 0xFFFFFF)]
for sheet in sheets {
    ctx.saveGState()
    ctx.translateBy(x: pivot.x, y: pivot.y)
    ctx.rotate(by: sheet.angle * .pi / 180)
    let rect = CGRect(x: -215, y: -640, width: 430, height: 640)
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: color(0x000000, 0.35))
    ctx.addPath(roundedRect(rect, 26))
    ctx.setFillColor(color(sheet.fill))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    if sheet.angle == 0 {
        ctx.setStrokeColor(color(0xB9D3DA))
        ctx.setLineWidth(5)
        for i in 0..<7 {
            let y = rect.minY + 150 + CGFloat(i) * 62
            ctx.move(to: CGPoint(x: rect.minX + 36, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX - 36, y: y))
        }
        ctx.strokePath()
    }
    ctx.restoreGState()
}

// Pen stroke on the front sheet.
ctx.saveGState()
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.setLineWidth(26)
ctx.setStrokeColor(color(0x0A4A52))
let stroke = CGMutablePath()
stroke.move(to: CGPoint(x: 360, y: 440))
stroke.addCurve(to: CGPoint(x: 470, y: 400), control1: CGPoint(x: 390, y: 330), control2: CGPoint(x: 440, y: 330))
stroke.addCurve(to: CGPoint(x: 560, y: 470), control1: CGPoint(x: 510, y: 460), control2: CGPoint(x: 520, y: 500))
stroke.addCurve(to: CGPoint(x: 670, y: 380), control1: CGPoint(x: 600, y: 440), control2: CGPoint(x: 620, y: 360))
ctx.addPath(stroke)
ctx.strokePath()
ctx.restoreGState()

// Band tying the sheaf.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 8), blur: 16, color: color(0x000000, 0.3))
let band = CGRect(x: 282, y: 640, width: 460, height: 96)
ctx.addPath(roundedRect(band, 20))
ctx.setFillColor(color(0xF2A93B))
ctx.fillPath()
ctx.restoreGState()
ctx.setStrokeColor(color(0xC97F14, 0.6))
ctx.setLineWidth(5)
ctx.move(to: CGPoint(x: 300, y: 688))
ctx.addLine(to: CGPoint(x: 724, y: 688))
ctx.strokePath()

let image = ctx.makeImage()!
let png = iconSet.appending(path: "AppIcon.png")
let dest = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write icon") }

let iconJSON = """
{
  "images" : [
    { "filename" : "AppIcon.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try iconJSON.write(to: iconSet.appending(path: "Contents.json"), atomically: true, encoding: .utf8)

let accentJSON = """
{
  "colors" : [
    {
      "color" : { "color-space" : "srgb", "components" : { "alpha" : "1.000", "blue" : "0.502", "green" : "0.486", "red" : "0.059" } },
      "idiom" : "universal"
    },
    {
      "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ],
      "color" : { "color-space" : "srgb", "components" : { "alpha" : "1.000", "blue" : "0.745", "green" : "0.722", "red" : "0.239" } },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
"""
try accentJSON.write(to: accentSet.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
try """
{ "info" : { "author" : "xcode", "version" : 1 } }
""".write(to: catalog.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("Wrote app icon and accent color to \(catalog.path)")
