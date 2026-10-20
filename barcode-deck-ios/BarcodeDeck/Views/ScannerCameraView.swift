import SwiftUI
import VisionKit

/// How many consecutive identical reads confirm a capture. Accuracy over
/// speed: misreads of large codes rarely repeat identically.
let requiredReads = 3

/// How often the scan cycle restarts. VisionKit decodes each tracked item
/// once; restarting forces a fresh, independent read of what is in view.
private let restartInterval: Duration = .milliseconds(400)

/// UIKit wrapper around VisionKit's DataScannerViewController. Confirms a
/// capture after `requiredReads` consecutive identical reads (see
/// `ReadVerifier`) — the scan cycle restarts every `restartInterval` so
/// each read is fresh — or reports `onUnavailable` when scanning cannot
/// start (no camera — e.g. Simulator — or permission denied).
struct ScannerCameraView: UIViewControllerRepresentable {
    let onDetected: (_ value: String, _ symbology: String?) -> Void
    let onProgress: (_ verifiedReads: Int) -> Void
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
            return
        }
        context.coordinator.startRestartLoop(controller)
    }

    static func dismantleUIViewController(
        _ uiViewController: DataScannerViewController,
        coordinator: Coordinator
    ) {
        coordinator.restartLoop?.cancel()
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
        /// Periodic task that restarts scanning to force fresh reads.
        var restartLoop: Task<Void, Never>?
        private var verifier = ReadVerifier(requiredReads: requiredReads)

        init(parent: ScannerCameraView) {
            self.parent = parent
        }

        func reportUnavailable(_ callback: @escaping () -> Void) {
            guard !hasFinished else { return }
            hasFinished = true
            restartLoop?.cancel()
            Task { @MainActor in
                callback()
            }
        }

        /// Restarts the scan cycle every `restartInterval` until a capture
        /// is confirmed: stopping clears the tracked items, so the next
        /// `didAdd` is a new, independent decode of what is in view.
        func startRestartLoop(_ controller: DataScannerViewController) {
            restartLoop?.cancel()
            restartLoop = Task { [weak self, weak controller] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: restartInterval)
                    guard let self, let controller, !self.hasFinished else { return }
                    controller.stopScanning()
                    try? controller.startScanning()
                }
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

                let symbology = BarcodeValidation.name(for: barcode.observation.symbology)
                if verifier.onRead(value: value, symbology: symbology) {
                    hasFinished = true
                    restartLoop?.cancel()
                    dataScanner.stopScanning()
                    let capturedValue = value
                    let capturedSymbology = symbology
                    Task { @MainActor in
                        let parent = self.parent
                        parent.onDetected(capturedValue, capturedSymbology)
                    }
                } else {
                    parent.onProgress(verifier.count)
                }
                return
            }
        }
    }
}
