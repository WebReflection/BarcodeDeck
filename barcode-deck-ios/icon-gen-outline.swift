// Outline variant of the "Barcode Deck" icon: two white cards with black bars,
// black outline around each card, transparent outside the outline.
// Run: swift icon-gen-outline.swift <output-dir>

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
}

let white = color(1, 1, 1)
let pureBlack = color(0, 0, 0)

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func barcodePattern(seed: Int, count: Int) -> [(Bool, CGFloat)] {
    var state = UInt64(truncatingIfNeeded: seed) &* 0x9E3779B97F4A7C15 &+ 0x51_7C_C1_B7_27_22_0A_95
    func rnd() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state >> 33
    }
    var result: [(Bool, CGFloat)] = []
    var isBar = true
    for _ in 0..<count {
        result.append((isBar, CGFloat(1 + rnd() % 3)))
        isBar.toggle()
    }
    return result
}

func drawBars(context: CGContext, rect: CGRect, color: CGColor, pattern: [(Bool, CGFloat)]) {
    let total = pattern.reduce(CGFloat(0)) { $0 + $1.1 }
    let unit = rect.width / total
    var x = rect.minX
    for (isBar, w) in pattern {
        if isBar {
            context.setFillColor(color)
            context.fill(CGRect(x: x, y: rect.minY, width: w * unit, height: rect.height))
        }
        x += w * unit
    }
}

func drawCard(
    context: CGContext,
    center: CGPoint,
    angle: CGFloat,
    size: CGSize,
    cardColor: CGColor,
    barColor: CGColor,
    outlineColor: CGColor?,
    outlineWidth: CGFloat,
    seed: Int
) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: angle)

    let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)

    // Card fill
    context.addPath(roundedRect(rect, radius: 44))
    context.setFillColor(cardColor)
    context.fillPath()

    // Name line
    let lineRect = CGRect(
        x: rect.minX + size.width * 0.12,
        y: rect.minY + size.height * 0.70,
        width: size.width * 0.42,
        height: size.height * 0.085
    )
    context.setFillColor(barColor)
    context.fill(lineRect)

    // Barcode
    let barsRect = CGRect(
        x: rect.minX + size.width * 0.12,
        y: rect.minY + size.height * 0.18,
        width: size.width * 0.76,
        height: size.height * 0.38
    )
    drawBars(context: context, rect: barsRect, color: barColor, pattern: barcodePattern(seed: seed, count: 30))

    // Outline (drawn last so it sits on top of the fill edges)
    if let outlineColor, outlineWidth > 0 {
        context.addPath(roundedRect(rect, radius: 44))
        context.setStrokeColor(outlineColor)
        context.setLineWidth(outlineWidth)
        context.strokePath()
    }

    context.restoreGState()
}

func render(lineWidth: CGFloat, background: CGColor?, to url: URL) {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    if let background {
        ctx.setFillColor(background)
        ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    }

    let cardSize = CGSize(width: 640, height: 400)

    drawCard(
        context: ctx, center: CGPoint(x: S * 0.46, y: S * 0.58), angle: -0.14,
        size: cardSize, cardColor: white, barColor: pureBlack,
        outlineColor: pureBlack, outlineWidth: lineWidth, seed: 7
    )
    drawCard(
        context: ctx, center: CGPoint(x: S * 0.54, y: S * 0.42), angle: 0.09,
        size: cardSize, cardColor: white, barColor: pureBlack,
        outlineColor: pureBlack, outlineWidth: lineWidth, seed: 42
    )

    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        print("failed to write \(url)")
        return
    }
    print("wrote \(url.path)")
}

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

render(lineWidth: 18, background: nil, to: outDir.appendingPathComponent("icon-E-outline-transparent.png"))
render(lineWidth: 26, background: nil, to: outDir.appendingPathComponent("icon-E-outline-thick-transparent.png"))
render(lineWidth: 18, background: pureBlack, to: outDir.appendingPathComponent("icon-E-outline-on-black.png"))
