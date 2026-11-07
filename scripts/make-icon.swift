// Draws Island's app icon (1024 x 1024 PNG) with CoreGraphics only: a near-black rounded square, a cyan notch pill
// hanging from its top edge (the "island"), and the white blob-buddy mascot with its focus face under it.
//
// Usage: swift scripts/make-icon.swift <output.png>
// The mascot is the exact shape and face used in the app (Sources/IslandUI/Mascots/BlobMascotView.swift, 26-unit space).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas = 1024
let output = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: colorSpace,
        components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha])!
}

guard let context = CGContext(
    data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("could not create the drawing context") }

// Work with the origin at the top left, y pointing down, like the app's own coordinates.
context.translateBy(x: 0, y: CGFloat(canvas))
context.scaleBy(x: 1, y: -1)
context.setAllowsAntialiasing(true)
context.interpolationQuality = .high

// MARK: The rounded square (the standard macOS icon grid: 824 pt inside a 100 pt margin)

let square = CGRect(x: 100, y: 100, width: 824, height: 824)
let squarePath = CGPath(roundedRect: square, cornerWidth: 185, cornerHeight: 185, transform: nil)

context.saveGState()
context.addPath(squarePath)
context.clip()
let background = CGGradient(
    colorsSpace: colorSpace, colors: [color(0x09090B), color(0x0B1F25)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(
    background, start: CGPoint(x: 512, y: square.minY), end: CGPoint(x: 512, y: square.maxY), options: [])

// A soft cyan glow rising from the pill, so the dark square is not flat.
let glow = CGGradient(
    colorsSpace: colorSpace, colors: [color(0x22D3EE, alpha: 0.20), color(0x22D3EE, alpha: 0)] as CFArray, locations: [0, 1])!
context.drawRadialGradient(
    glow, startCenter: CGPoint(x: 512, y: 150), startRadius: 0, endCenter: CGPoint(x: 512, y: 150), endRadius: 520, options: [])
context.restoreGState()

// A hairline edge so the square holds its shape on dark backgrounds.
context.addPath(squarePath)
context.setStrokeColor(color(0xFFFFFF, alpha: 0.10))
context.setLineWidth(3)
context.strokePath()

// MARK: The notch pill, hanging from the top edge

let pill = CGMutablePath()
let k: CGFloat = 0.5523 * 50
pill.move(to: CGPoint(x: 362, y: 100))
pill.addLine(to: CGPoint(x: 662, y: 100))
pill.addLine(to: CGPoint(x: 662, y: 150))
pill.addCurve(to: CGPoint(x: 612, y: 200), control1: CGPoint(x: 662, y: 150 + k), control2: CGPoint(x: 612 + k, y: 200))
pill.addLine(to: CGPoint(x: 412, y: 200))
pill.addCurve(to: CGPoint(x: 362, y: 150), control1: CGPoint(x: 412 - k, y: 200), control2: CGPoint(x: 362, y: 150 + k))
pill.closeSubpath()

context.saveGState()
context.addPath(squarePath)
context.clip()
context.setShadow(offset: .zero, blur: 50, color: color(0x22D3EE, alpha: 0.55))
context.addPath(pill)
context.setFillColor(color(0x22D3EE))
context.fillPath()
context.restoreGState()

// The camera dot of the notch.
context.setFillColor(color(0x0B1F25, alpha: 0.85))
context.fillEllipse(in: CGRect(x: 512 - 15, y: 163 - 15, width: 30, height: 30))

// MARK: The mascot (26-unit design space, scaled by 24 and placed under the pill)

context.saveGState()
context.translateBy(x: 200, y: 262)
context.scaleBy(x: 24, y: 24)

let body = CGMutablePath()
let kb: CGFloat = 0.5523 * 9
body.move(to: CGPoint(x: 4, y: 22))
body.addLine(to: CGPoint(x: 4, y: 12))
body.addCurve(to: CGPoint(x: 13, y: 3), control1: CGPoint(x: 4, y: 12 - kb), control2: CGPoint(x: 13 - kb, y: 3))
body.addCurve(to: CGPoint(x: 22, y: 12), control1: CGPoint(x: 13 + kb, y: 3), control2: CGPoint(x: 22, y: 12 - kb))
for (x, y) in [(22.0, 22.0), (19, 20), (16, 22), (13, 20), (10, 22), (7, 20)] {
    body.addLine(to: CGPoint(x: x, y: y))
}
body.closeSubpath()

// A faint cyan glow around the white body (the shadow blur is in device pixels, not design units).
context.setShadow(offset: .zero, blur: 70, color: color(0x22D3EE, alpha: 0.55))
context.addPath(body)
context.setFillColor(color(0xFFFFFF))
context.fillPath()
context.setShadow(offset: .zero, blur: 0, color: nil)

// The focus face: two dot eyes and two frowning brows.
let ink = color(0x121212)
context.setFillColor(ink)
for x in [10.0, 16.0] {
    context.fillEllipse(in: CGRect(x: x - 1.6, y: 12 - 1.6, width: 3.2, height: 3.2))
}
context.setStrokeColor(ink)
context.setLineWidth(1.3)
context.setLineCap(.round)
context.move(to: CGPoint(x: 8.6, y: 6.8))
context.addLine(to: CGPoint(x: 12, y: 8.2))
context.move(to: CGPoint(x: 17.4, y: 6.8))
context.addLine(to: CGPoint(x: 14, y: 8.2))
context.strokePath()
context.restoreGState()

// MARK: Write the PNG

guard let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not write \(output)") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(output)") }
print("Wrote \(output)")
