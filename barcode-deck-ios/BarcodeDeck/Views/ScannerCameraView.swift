import SwiftUI
import VisionKit

/// UIKit wrapper around VisionKit's DataScannerViewController, configured
/// for 1D barcodes only. Calls `onDetected` once on the first locked barcode,
/// or `onUnavailable` when scanning cannot start (no camera — e.g. Simulator —
/// or permission denied).
struct ScannerCameraView: UIViewControllerRepresentable {
    let onDetected: (_ value: String, _ symbology: String?) -> Void
    let onUnavailable: () -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: BarcodeValidation.scanSymbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: false
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.parent = self
        guard !context.coordinator.hasStarted else { return }
        context.coordinator.hasStarted = true
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
            context.coordinator.reportUnavailable(onUnavailable)
            return
        }
        do {
            try controller.startScanning()
        } catch {
            context.coordinator.reportUnavailable(onUnavailable)
        }
    }

    static func dismantleUIViewController(
        _ uiViewController: DataScannerViewController,
        coordinator: Coordinator
    ) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: ScannerCameraView
        /// Guard so we report capture/unavailability only once per session.
        var hasFinished = false
        var hasStarted = false

        init(parent: ScannerCameraView) {
            self.parent = parent
        }

        func reportUnavailable(_ callback: @escaping () -> Void) {
            guard !hasFinished else { return }
            hasFinished = true
            Task { @MainActor in
                callback()
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard !hasFinished else { return }
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let value = barcode.payloadStringValue,
                      !value.isEmpty
                else { continue }

                hasFinished = true
                dataScanner.stopScanning()
                let symbology = BarcodeValidation.name(for: barcode.observation.symbology)
                let capturedValue = value
                Task { @MainActor in
                    parent.onDetected(capturedValue, symbology)
                }
                return
            }
        }
    }
}
