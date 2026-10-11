import SwiftUI

/// Renders a scanner-readable EAN-13/UPC-A barcode as pure vector graphics.
///
/// Sizing rules (from the plan):
/// - Fixed *physical* size, never proportional to screen size: magnification
///   clamped to the GS1 80%–200% range (target ≤ 150%).
/// - Bar widths snapped to whole device physical pixels — no anti-aliasing.
/// - Quiet zones (11 modules each side) reserved inside the layout.
struct BarcodeView: View {
    let value: String
    let symbology: String?
    /// Ephemeral pinch-zoom multiplier (1.0 = the calculated perfect size).
    /// Never persisted — presentation mode always starts at 1.0.
    var zoomScale: CGFloat = 1.0

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let rendered = BarcodePattern.modulesForPresentation(value: value, symbology: symbology)

            VStack(spacing: 6) {
                Canvas { context, size in
                    guard let rendered else { return }
                    drawBars(
                        rendered.modules,
                        quietModules: rendered.quietModules,
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
            .opacity(rendered == nil ? 0 : 1)
        }
    }

    private func drawBars(
        _ modules: [Bool],
        quietModules: Int,
        zoomScale: CGFloat,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let scale = max(displayScale, 1)
        // Points are 163 per inch on iOS regardless of display scale
        // (scale only changes pixels per point).
        let mmPerPoint = 25.4 / 163.0
        let totalModules = modules.count + 2 * quietModules

        // Magnification that fits the available width, clamped to GS1 80–200%,
        // then scaled by the user's ephemeral pinch-zoom (if any).
        let fitMagnification = Double(size.width) * mmPerPoint
            / (Double(totalModules) * BarcodePattern.nominalModuleWidthMM)
        let magnification = min(1.5, max(0.8, fitMagnification)) * Double(zoomScale)

        // Snap the module width to whole physical pixels.
        var modulePixels = (BarcodePattern.nominalModuleWidthMM * magnification / mmPerPoint * scale)
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

        // Never stretch the code tall: cap the bar height at ~60% of the
        // symbol's own width (EAN-13-like aspect ratio), centered vertically.
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

#Preview {
    BarcodeView(value: "4006381333931", symbology: "EAN-13")
        .padding()
}
