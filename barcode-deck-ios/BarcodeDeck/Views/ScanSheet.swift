import SwiftUI
import VisionKit

/// Full-screen camera scanner. On a locked barcode it fires `onCapture`
/// (after a success haptic); "Type it in" fires `onManualEntry`. Both close
/// the scanner — the caller then presents the add form.
struct ScanSheet: View {
    let onCapture: (_ value: String, _ symbology: String?) -> Void
    let onManualEntry: () -> Void
    let onCancel: () -> Void

    @State private var cameraUnavailable = false

    var body: some View {
        ZStack {
            if cameraUnavailable || !DataScannerViewController.isSupported {
                fallbackView
            } else {
                ScannerCameraView(
                    onDetected: handleCapture,
                    onUnavailable: { cameraUnavailable = true }
                )
                .ignoresSafeArea()
                overlay
            }
        }
        .background(Color.black)
        .statusBarHidden()
    }

    // MARK: - Camera UI

    private var overlay: some View {
        VStack(spacing: 24) {
            Text("Scan barcode")
                .font(.headline)
                .foregroundStyle(.white)

            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .frame(height: 180)
                .padding(.horizontal, 48)

            Text("Align the barcode inside the frame")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            HStack {
                Button("Type it in", action: onManualEntry)
                Spacer()
                Button("Cancel", action: onCancel)
            }
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    // MARK: - Fallback (Simulator / no camera / denied permission)

    private var fallbackView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "camera.badge.ellipsis")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.6))
            Text("Camera unavailable")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(
                "Scanning needs a camera — on Simulator or without camera " +
                "permission you can type the barcode instead."
            )
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.7))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    onManualEntry()
                } label: {
                    Text("Type it in")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onCancel()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func handleCapture(value: String, symbology: String?) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onCapture(value, symbology)
    }
}

#Preview("Fallback") {
    ScanSheet(
        onCapture: { _, _ in },
        onManualEntry: {},
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}
