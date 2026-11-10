// Draws Island's app icon (1024 x 1024 PNG) with CoreGraphics only: a light "glass" rounded square, and the open island
// hanging from its top edge: a near-black panel holding six feature tiles (Tasks, GitHub, Teams, Calendar, Player,
// Browser) and a progress bar. The camera dot at the top is the notch's.
//
// Usage: swift scripts/make-icon.swift <output.png>
//
// Everything is drawn in an 824-unit space (the standard macOS icon grid: an 824 pt square inside a 100 pt margin), so the
// numbers below read the same as the design they came from. `at(_:_:)` moves a point from that space onto the canvas.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas = 1024
let margin: CGFloat = 100
let output = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        colorSpace: colorSpace,
        components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha])!
}

func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: margin + x, y: margin + y) }
func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
    CGRect(x: margin + x, y: margin + y, width: width, height: height)
}

// The palette ("Glass"): a white-to-silver tile, an ink-black panel, and three accents.
let panelInk = color(0x0D1014)
let blue: UInt32 = 0x0A84FF
let violet: UInt32 = 0xBF5AF2
let orange: UInt32 = 0xFF9F0A

guard let context = CGContext(
    data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("could not create the drawing context") }

// Work with the origin at the top left, y pointing down, like the app's own coordinates.
context.translateBy(x: 0, y: CGFloat(canvas))
context.scaleBy(x: 1, y: -1)
context.setAllowsAntialiasing(true)
context.interpolationQuality = .high

// MARK: The rounded square

let square = rect(0, 0, 824, 824)
let squarePath = CGPath(roundedRect: square, cornerWidth: 184, cornerHeight: 184, transform: nil)

// Everything except the hairline edge is clipped to the square, so the panel can hang from its very top edge.
context.saveGState()
context.addPath(squarePath)
context.clip()
let background = CGGradient(colorsSpace: colorSpace, colors: [color(0xFFFFFF), color(0xD5DBE4)] as CFArray, locations: [0, 1])!
context.drawLinearGradient(
    background, start: CGPoint(x: 512, y: square.minY), end: CGPoint(x: 512, y: square.maxY), options: [])

// MARK: The open island, hanging from the top edge

let panel = CGMutablePath()
let k: CGFloat = 0.5523 * 140        // a quarter circle of radius 140, as a Bezier curve
panel.move(to: at(122, 0))
panel.addLine(to: at(702, 0))
panel.addLine(to: at(702, 430))
panel.addCurve(to: at(562, 570), control1: at(702, 430 + k), control2: at(562 + k, 570))
panel.addLine(to: at(262, 570))
panel.addCurve(to: at(122, 430), control1: at(262 - k, 570), control2: at(122, 430 + k))
panel.closeSubpath()
context.addPath(panel)
context.setFillColor(panelInk)
context.fillPath()

// The notch's camera dot.
context.setFillColor(color(0xF5F7FA, alpha: 0.35))
context.fillEllipse(in: rect(412 - 14, 58 - 14, 28, 28))

// MARK: Six feature tiles, each with a small symbol

let tileSize: CGFloat = 128
let tiles: [(x: CGFloat, y: CGFloat, color: UInt32)] = [
    (188, 120, blue), (348, 120, violet), (508, 120, orange),
    (188, 280, orange), (348, 280, blue), (508, 280, violet),
]
for tile in tiles {
    context.addPath(CGPath(roundedRect: rect(tile.x, tile.y, tileSize, tileSize), cornerWidth: 34, cornerHeight: 34, transform: nil))
    context.setFillColor(color(tile.color))
    context.fillPath()
}

/// Draws a symbol in the middle of a tile: `draw` works in a space centred on (0, 0).
func symbol(centerX: CGFloat, centerY: CGFloat, _ draw: () -> Void) {
    context.saveGState()
    let c = at(centerX, centerY)
    context.translateBy(x: c.x, y: c.y)
    context.setStrokeColor(panelInk)
    context.setFillColor(panelInk)
    context.setLineWidth(12)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    draw()
    context.restoreGState()
}

func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) { context.strokeEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)) }

// Tasks: a check mark.
symbol(centerX: 252, centerY: 184) {
    context.move(to: CGPoint(x: -26, y: 2))
    context.addLine(to: CGPoint(x: -8, y: 20))
    context.addLine(to: CGPoint(x: 28, y: -20))
    context.strokePath()
}
// GitHub: a pull request (two dots joined by a line, a third dot with a bent line).
symbol(centerX: 412, centerY: 184) {
    circle(-20, -26, 9)
    circle(-20, 26, 9)
    circle(22, 26, 9)
    context.move(to: CGPoint(x: -20, y: -17))
    context.addLine(to: CGPoint(x: -20, y: 17))
    context.move(to: CGPoint(x: 22, y: 17))
    context.addLine(to: CGPoint(x: 22, y: -8))
    context.addQuadCurve(to: CGPoint(x: 10, y: -20), control: CGPoint(x: 22, y: -20))
    context.addLine(to: CGPoint(x: 0, y: -20))
    context.strokePath()
}
// Teams: a speech bubble.
symbol(centerX: 572, centerY: 184) {
    context.move(to: CGPoint(x: -30, y: -24))
    context.addLine(to: CGPoint(x: 30, y: -24))
    context.addLine(to: CGPoint(x: 30, y: 14))
    context.addLine(to: CGPoint(x: -4, y: 14))
    context.addLine(to: CGPoint(x: -24, y: 32))
    context.addLine(to: CGPoint(x: -24, y: 14))
    context.addLine(to: CGPoint(x: -30, y: 14))
    context.closePath()
    context.strokePath()
}
// Calendar: a page with two binder rings.
symbol(centerX: 252, centerY: 344) {
    context.addPath(CGPath(roundedRect: CGRect(x: -30, y: -22, width: 60, height: 52), cornerWidth: 10, cornerHeight: 10, transform: nil))
    context.move(to: CGPoint(x: -30, y: -4))
    context.addLine(to: CGPoint(x: 30, y: -4))
    context.move(to: CGPoint(x: -12, y: -32))
    context.addLine(to: CGPoint(x: -12, y: -16))
    context.move(to: CGPoint(x: 12, y: -32))
    context.addLine(to: CGPoint(x: 12, y: -16))
    context.strokePath()
}
// Player: a play triangle.
symbol(centerX: 412, centerY: 344) {
    context.move(to: CGPoint(x: -14, y: -26))
    context.addLine(to: CGPoint(x: 28, y: 0))
    context.addLine(to: CGPoint(x: -14, y: 26))
    context.closePath()
    context.drawPath(using: .fillStroke)
}
// Browser: a globe.
symbol(centerX: 572, centerY: 344) {
    circle(0, 0, 30)
    context.strokeEllipse(in: CGRect(x: -13, y: -30, width: 26, height: 60))
    context.move(to: CGPoint(x: -30, y: 0))
    context.addLine(to: CGPoint(x: 30, y: 0))
    context.strokePath()
}

// MARK: A progress bar along the bottom of the panel

context.addPath(CGPath(roundedRect: rect(188, 458, 448, 22), cornerWidth: 11, cornerHeight: 11, transform: nil))
context.setFillColor(color(0xF5F7FA, alpha: 0.2))
context.fillPath()
context.addPath(CGPath(roundedRect: rect(188, 458, 250, 22), cornerWidth: 11, cornerHeight: 11, transform: nil))
context.setFillColor(color(blue))
context.fillPath()
context.restoreGState()

// A hairline edge so the square holds its shape on white backgrounds.
context.addPath(squarePath)
context.setStrokeColor(color(0x000000, alpha: 0.14))
context.setLineWidth(3)
context.strokePath()

// MARK: Write the PNG

guard let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("could not write \(output)") }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(output)") }
print("Wrote \(output)")
