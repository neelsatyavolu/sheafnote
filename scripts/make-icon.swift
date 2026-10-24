#!/usr/bin/env swift
// Generates the Sheafnote app icon (DESIGN.md): a cream folded sheet on a tangerine background with one ink swoosh.
// Usage: swift scripts/make-icon.swift   (writes App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconSet = root.appending(path: "App/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.translateBy(x: 0, y: CGFloat(size))   // top-left origin
ctx.scaleBy(x: 1, y: -1)

// Tangerine background with a gentle lift toward the top.
let bg = CGGradient(colorsSpace: cs, colors: [color(0xFF6A3F), color(0xF2542D)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: .zero, end: CGPoint(x: 0, y: CGFloat(size)), options: [])

// The cream sheet, tilted a little, with its top-right corner folded over.
let sheet = CGRect(x: 262, y: 176, width: 500, height: 672)
let fold: CGFloat = 170
let radius: CGFloat = 44
let sheetPath = CGMutablePath()
sheetPath.move(to: CGPoint(x: sheet.minX + radius, y: sheet.minY))
sheetPath.addLine(to: CGPoint(x: sheet.maxX - fold, y: sheet.minY))
sheetPath.addLine(to: CGPoint(x: sheet.maxX, y: sheet.minY + fold))
sheetPath.addLine(to: CGPoint(x: sheet.maxX, y: sheet.maxY - radius))
sheetPath.addArc(tangent1End: CGPoint(x: sheet.maxX, y: sheet.maxY), tangent2End: CGPoint(x: sheet.maxX - radius, y: sheet.maxY), radius: radius)
sheetPath.addLine(to: CGPoint(x: sheet.minX + radius, y: sheet.maxY))
sheetPath.addArc(tangent1End: CGPoint(x: sheet.minX, y: sheet.maxY), tangent2End: CGPoint(x: sheet.minX, y: sheet.maxY - radius), radius: radius)
sheetPath.addLine(to: CGPoint(x: sheet.minX, y: sheet.minY + radius))
sheetPath.addArc(tangent1End: CGPoint(x: sheet.minX, y: sheet.minY), tangent2End: CGPoint(x: sheet.minX + radius, y: sheet.minY), radius: radius)
sheetPath.closeSubpath()

let flap = CGMutablePath()
flap.move(to: CGPoint(x: sheet.maxX - fold, y: sheet.minY))
flap.addLine(to: CGPoint(x: sheet.maxX, y: sheet.minY + fold))
flap.addLine(to: CGPoint(x: sheet.maxX - fold, y: sheet.minY + fold))
flap.closeSubpath()

ctx.saveGState()
ctx.translateBy(x: sheet.midX, y: sheet.midY)
ctx.rotate(by: -5 * .pi / 180)
ctx.translateBy(x: -sheet.midX, y: -sheet.midY)
ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 46, color: color(0x6B1D08, 0.38))
ctx.addPath(sheetPath)
ctx.setFillColor(color(0xFFF6E4))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.addPath(flap)
ctx.setFillColor(color(0xEBDBBB))
ctx.fillPath()
ctx.restoreGState()

// One bold ink swoosh, tapered at both ends, across the sheet.
func bezier(_ t: CGFloat, _ p: [CGPoint]) -> CGPoint {
    let u = 1 - t
    return CGPoint(x: u*u*u*p[0].x + 3*u*u*t*p[1].x + 3*u*t*t*p[2].x + t*t*t*p[3].x,
                   y: u*u*u*p[0].y + 3*u*u*t*p[1].y + 3*u*t*t*p[2].y + t*t*t*p[3].y)
}
let spine = [CGPoint(x: 150, y: 700), CGPoint(x: 380, y: 470), CGPoint(x: 560, y: 860), CGPoint(x: 880, y: 380)]
let steps = 120
var upper: [CGPoint] = [], lower: [CGPoint] = []
for i in 0...steps {
    let t = CGFloat(i) / CGFloat(steps)
    let p = bezier(t, spine)
    let a = bezier(min(1, t + 0.002), spine), b = bezier(max(0, t - 0.002), spine)
    let len = hypot(a.x - b.x, a.y - b.y)
    let nx = -(a.y - b.y) / len, ny = (a.x - b.x) / len
    let half = 8 + 44 * pow(sin(.pi * t), 0.8)
    upper.append(CGPoint(x: p.x + nx * half, y: p.y + ny * half))
    lower.append(CGPoint(x: p.x - nx * half, y: p.y - ny * half))
}
let swoosh = CGMutablePath()
swoosh.move(to: upper[0])
for p in upper.dropFirst() + lower.reversed() { swoosh.addLine(to: p) }
swoosh.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 18, color: color(0x2B2420, 0.35))
ctx.addPath(swoosh)
ctx.setFillColor(color(0x2B2420))
ctx.fillPath()
ctx.restoreGState()

let png = iconSet.appending(path: "AppIcon.png")
let dest = CGImageDestinationCreateWithURL(png as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("could not write icon") }
print("Wrote \(png.path)")
