// App icon generator — draws "Barcode Deck" icon candidates with CoreGraphics.
// Run: swift icon-gen.swift
// Output: icon-variants/icon-<Name>.png (1024×1024, no transparency)

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
}

struct Variant {
    let name: String
    let background: CGColor
    let backCard: CGColor
    let backBars: CGColor
    let frontCard: CGColor
    let frontBars: CGColor
}

// Deterministic pseudo-random barcode pattern: alternating bar/space widths 1..3.
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

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
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
    seed: Int
) {
    context.saveGState()
    context.translateBy(x: center.x, y: center.y)
    context.rotate(by: angle)

    let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
    context.addPath(roundedRect(rect, radius: 44))
    context.setFillColor(cardColor)
    context.fillPath()

    // Name line (short, thick) — reads as the card's title
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

    context.restoreGState()
}

func render(_ variant: Variant) {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(
        data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
        space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    ctx.setFillColor(variant.background)
    ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

    let cardSize = CGSize(width: 640, height: 400)

    // Back card: rotated counter-clockwise, shifted up
    drawCard(
        context: ctx, center: CGPoint(x: S * 0.46, y: S * 0.58), angle: -0.14,
        size: cardSize, cardColor: variant.backCard, barColor: variant.backBars, seed: 7
    )
    // Front card: rotated clockwise, shifted down
    drawCard(
        context: ctx, center: CGPoint(x: S * 0.54, y: S * 0.42), angle: 0.09,
        size: cardSize, cardColor: variant.frontCard, barColor: variant.frontBars, seed: 42
    )

    let image = ctx.makeImage()!
    let url = outDir.appendingPathComponent("icon-\(variant.name).png")
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        print("failed to write \(url)")
        return
    }
    print("wrote \(url.path)")
}

let darkGreen = color(0.0, 0.32, 0.12)
let accentGreen = color(0.0, 0.56, 0.0)
let nearBlack = color(0.07, 0.07, 0.07)
let white = color(1, 1, 1)
let pureBlack = color(0, 0, 0)

let variants = [
    // A: green + white only — matches the app accent
    Variant(name: "A-green-white", background: darkGreen, backCard: white, backBars: darkGreen,
            frontCard: white, frontBars: darkGreen),
    // B: pure black & white, dark background
    Variant(name: "B-mono-dark", background: nearBlack, backCard: white, backBars: pureBlack,
            frontCard: white, frontBars: pureBlack),
    // C: pure black & white, white background
    Variant(name: "C-mono-light", background: white, backCard: pureBlack, backBars: white,
            frontCard: white, frontBars: pureBlack),
    // D: green background, black bars on white cards
    Variant(name: "D-green-black", background: accentGreen, backCard: white, backBars: pureBlack,
            frontCard: white, frontBars: pureBlack),
]

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for variant in variants {
    render(variant)
}
