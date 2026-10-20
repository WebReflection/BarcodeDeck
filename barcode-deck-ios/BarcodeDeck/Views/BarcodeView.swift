import SwiftUI

/// Renders a scanner-readable barcode as pure vector graphics.
///
/// Sizing rules (mirroring Android):
/// - 1D: fixed *physical* size, never proportional to screen size —
///   magnification clamped to 80%–200% of the symbology's nominal module
///   width (target ≤ 150%).
/// - 2D (QR): scaled to fill the available square, snapped to whole device
///   pixels; the quiet zone is the surrounding white layout.
/// - Bar widths snapped to whole device physical pixels — no anti-aliasing.
/// - 1D bar height capped at ~60% of the symbol's own width.
struct BarcodeView: View {
    let value: String
    let symbology: String?
    /// Ephemeral pinch-zoom multiplier (1.0 = the calculated perfect size).
    /// Never persisted — presentation mode always starts at 1.0.
    var zoomScale: CGFloat = 1.0

    @Environment(\.displayScale) private var displayScale

    /// Maximum characters of a QR payload previewed under the symbol.
    private static let previewChars = 64

    private var preview: String {
        value.count <= Self.previewChars
            ? value
            : String(value.prefix(Self.previewChars)) + "…"
    }

    var body: some View {
        GeometryReader { proxy in
            switch BarcodePattern.presentationBarcode(value: value, symbology: symbology) {
            case .linear(let modules, let quietModules, let nominalModuleWidthMM):
                VStack(spacing: 6) {
                    Canvas { context, size in
                        drawBars(
                            modules,
                            quietModules: quietModules,
                            nominalModuleWidthMM: nominalModuleWidthMM,
                            zoomScale: zoomScale,
                            in: &context,
                            size: size
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Text(value)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .foregroundStyle(.black)
                }
            case .qr(let image, let moduleCount):
                // QR shows the symbol plus a preview of its value underneath
                // — payloads are often URLs, which the reader may also want
                // to open (the "open link" button lives in the presentation
                // header). The full payload always lives on the card itself
                // (and in the JSON export); long or binary content is never
                // rendered whole.
                VStack(spacing: 6) {
                    QRCodeContentView(
                        image: image,
                        moduleCount: moduleCount,
                        zoomScale: zoomScale
                    )
                    Text(preview)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .foregroundStyle(.black)
                }
            case nil:
                // Not renderable here: PresentationView shows its own text
                // fallback, so keep this view invisible.
                Color.clear
            }
        }
    }

    private func drawBars(
        _ modules: [Bool],
        quietModules: Int,
        nominalModuleWidthMM: Double,
        zoomScale: CGFloat,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let scale = max(displayScale, 1)
        // Points are 163 per inch on iOS regardless of display scale
        // (scale only changes pixels per point).
        let mmPerPoint = 25.4 / 163.0
        let totalModules = modules.count + 2 * quietModules

        // Magnification that fits the available width, clamped to 80–200%,
        // then scaled by the user's ephemeral pinch-zoom (if any).
        let fitMagnification = Double(size.width) * mmPerPoint
            / (Double(totalModules) * nominalModuleWidthMM)
        let magnification = min(1.5, max(0.8, fitMagnification)) * Double(zoomScale)

        // Snap the module width to whole physical pixels.
        var modulePixels = (nominalModuleWidthMM * magnification / mmPerPoint * scale)
            .rounded()
        modulePixels = max(2, modulePixels)
        // Safety: never overflow the available width.
        while Double(totalModules) * modulePixels > Double(size.width) * scale, modulePixels > 1 {
            modulePixels -= 1
        }
        let modulePoints = modulePixels / scale

        let drawnWidth = CGFloat(totalModules) * modulePoints
        var x0 = (size.width - drawnWidth) / 2
        x0 = (x0 * scale).rounded() / scale  // snap the origin to the pixel grid too

        // Never stretch the code tall: cap the bar height at ~60% of its own
        // width (EAN-13-like aspect ratio), centered vertically.
        let barHeight = min(size.height, drawnWidth * 0.6)
        let y0 = (size.height - barHeight) / 2

        var path = Path()
        for (index, isBar) in modules.enumerated() where isBar {
            let x = x0 + CGFloat(quietModules + index) * modulePoints
            path.addRect(CGRect(x: x, y: y0, width: modulePoints, height: barHeight))
        }
        context.fill(path, with: .color(.black))
    }
}

/// Square QR display: module size snapped to whole device pixels, zoom
/// applied and capped at the available box, quiet zone left as white
/// layout around the image (the background is always white here).
private struct QRCodeContentView: View {
    let image: CGImage
    let moduleCount: Int
    let zoomScale: CGFloat

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let totalModules = CGFloat(moduleCount + BarcodePattern.qrQuietModules * 2)
            let available = min(proxy.size.width, proxy.size.height)
            let capped = min(available * zoomScale, available)
            let modulePixels = max(1, (capped * displayScale / totalModules).rounded(.down))
            let side = modulePixels * totalModules / displayScale
            let imageSide = side * CGFloat(moduleCount) / totalModules

            Image(uiImage: UIImage(cgImage: image))
                .interpolation(.none)
                .resizable()
                .frame(width: imageSide, height: imageSide)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    BarcodeView(value: "4006381333931", symbology: "EAN-13")
        .padding()
}

#Preview("QR") {
    BarcodeView(value: "https://barcodedeck.dev", symbology: "QR Code")
        .padding()
}
