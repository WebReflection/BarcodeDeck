import SwiftData
import SwiftUI

/// Full-screen "the phone is the card" mode.
///
/// - Header (name) and description on top, barcode filling the remaining
///   vertical space.
/// - Screen stays awake while visible; brightness is left to the user.
///   An explicit, ephemeral one-off toggle can force max brightness for the
///   current presentation only — it is never persisted.
/// - Landscape while visible.
/// - Swipe (any direction, ≥ 100 pt) or tap exits back to the list.
struct PresentationView: View {
    let card: Card

    @Environment(\.dismiss) private var dismiss
    /// Ephemeral one-off "force max brightness" intent. Intentionally a
    /// plain @State: it dies with the view, so nothing is remembered between
    /// presentations.
    @State private var forceMaxBrightness = false
    /// Brightness to restore after a forced max-brightness session.
    @State private var savedBrightness: CGFloat?
    /// Ephemeral pinch-zoom: resets to 1.0 every time presentation mode opens.
    @State private var lastPinchScale: CGFloat = 1.0
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var isPinching = false

    /// Total zoom applied to the barcode, clamped to 0.5×–2.5×.
    private var barcodeZoom: CGFloat {
        min(2.5, max(0.5, lastPinchScale * pinchScale))
    }

    var body: some View {
        GeometryReader { proxy in
            if isQrCard {
                // QR: the symbol gets ALL the space between the header and
                // its value line (rendered by BarcodeView) — square codes
                // need the room, and the payload is only previewed on a
                // single line.
                VStack(spacing: 0) {
                    header(height: proxy.size.height)
                    BarcodeView(
                        value: card.displayBarcodeValue,
                        symbology: card.symbology,
                        zoomScale: barcodeZoom
                    )
                    .gesture(zoomGesture)
                }
                .padding(28)
            } else {
                VStack(spacing: 0) {
                    // Top half: name and description.
                    header(height: proxy.size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                    // Bottom half: the barcode, centered in the remaining space.
                    cardBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .padding(28)
            }
        }
        .background(Color.white)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: forceMaxBrightness) { _, enabled in
            if enabled {
                savedBrightness = screen.brightness
                screen.brightness = 1.0
            } else if let saved = savedBrightness {
                screen.brightness = saved
                savedBrightness = nil
            }
        }
        .onTapGesture {
            guard !isPinching else { return }
            dismiss()
        }
        .gesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    guard !isPinching else { return }
                    if abs(value.translation.height) > 100 || abs(value.translation.width) > 100 {
                        dismiss()
                    }
                }
        )
        .onAppear(perform: activate)
        .onDisappear(perform: deactivate)
        #if DEBUG
        .task {
            // Debug hook: auto-dismiss after 3 s so the rotation restore can
            // be verified headlessly (screenshots before/after dismissal).
            if ProcessInfo.processInfo.arguments.contains("--debug-auto-dismiss") {
                try? await Task.sleep(for: .seconds(3))
                dismiss()
            }
        }
        #endif
    }

    /// One-off max-brightness toggle, shown in the name row. The button's own
    /// gesture takes precedence over the tap/drag dismissal on the container,
    /// so toggling can never exit the presentation.
    private var brightnessToggle: some View {
        Button {
            forceMaxBrightness.toggle()
        } label: {
            Image(systemName: forceMaxBrightness ? "sun.max.fill" : "sun.max")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.black.opacity(forceMaxBrightness ? 0.85 : 0.35))
                .padding(12)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Force maximum brightness")
        .accessibilityHint("Applies to this presentation only and is not remembered")
    }

    /// The QR payload as an http(s) URL, when openable. Only http(s) is ever
    /// opened — other schemes (javascript:, mailto:, …) are ignored.
    private var httpURL: URL? {
        guard card.symbology == "QR Code" else { return nil }
        return BarcodeValidation.asHttpURL(card.displayBarcodeValue)
    }

    /// Opens the QR payload in the browser. Shown in the name row next to the
    /// brightness toggle; the button's own gesture takes precedence over the
    /// tap/drag dismissal on the container.
    private var openURLButton: some View {
        Button {
            if let url = httpURL {
                UIApplication.shared.open(url)
            }
        } label: {
            Image(systemName: "arrow.up.forward.square")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.black.opacity(0.85))
                .padding(12)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Open link in browser")
    }

    /// Name, optional description, and the top-end buttons ("open link"
    /// for http(s) QR payloads, max-brightness toggle).
    private func header(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // The toggle lives in the name row so it stays centered
            // with the top text line height, whatever the screen size.
            HStack(alignment: .center, spacing: 0) {
                Text(card.displayName)
                    .font(.system(size: min(44, height * 0.12), weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.black)
                Spacer(minLength: 12)
                if httpURL != nil {
                    openURLButton
                }
                brightnessToggle
            }

            if let description = card.displayDescription {
                Text(description)
                    .font(.system(size: min(22, height * 0.055)))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.black.opacity(0.65))
            }
        }
    }

    /// Whether this card presents as a square QR symbol (which uses the
    /// full-space layout) rather than a linear barcode.
    private var isQrCard: Bool {
        if case .qr = BarcodePattern.presentationBarcode(
            value: card.displayBarcodeValue,
            symbology: card.symbology
        ) { return true }
        return false
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { _ in isPinching = true }
            .updating($pinchScale) { value, state, _ in state = value }
            .onEnded { value in
                lastPinchScale = min(2.5, max(0.5, lastPinchScale * value))
                isPinching = false
            }
    }

    @ViewBuilder
    private var cardBody: some View {
        if BarcodePattern.presentationBarcode(
            value: card.displayBarcodeValue,
            symbology: card.symbology
        ) != nil {
            BarcodeView(value: card.displayBarcodeValue, symbology: card.symbology, zoomScale: barcodeZoom)
                .gesture(zoomGesture)
        } else {
            // Non-renderable symbology (Code 128, PDF417, …): show the value
            // as large text — readable by a human, not by a scanner.
            VStack(spacing: 12) {
                Text(card.displayBarcodeValue)
                    .font(.system(size: 44, weight: .semibold, design: .monospaced))
                    .minimumScaleFactor(0.3)
                    .lineLimit(2)
                    .foregroundStyle(.black)
                Text("Barcode display unavailable for this type")
                    .font(.footnote)
                    .foregroundStyle(.black.opacity(0.5))
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Brightness & orientation

    private var screen: UIScreen {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen ?? .main
    }

    private func activate() {
        // Keep the screen awake while presenting, but leave brightness to the
        // user: the scanning camera adapts to contrast, and a max-brightness
        // white background acts as a light source shining into the lens, which
        // can degrade reads of long codes. Max brightness remains available as
        // the explicit, ephemeral toggle above.
        UIApplication.shared.isIdleTimerDisabled = true

        // Remember how the user was holding the phone so the list can return
        // to it on exit. Unknown/face-up orientations default to portrait.
        // The actual restore request is issued after dismissal (see
        // CardListView.restoreOrientation) — mid-transition requests are
        // dropped by iOS.
        let device = UIDevice.current.orientation
        AppDelegate.restoreOrientation = device.isLandscape ? .landscape : .portrait
        AppDelegate.log.info("activate: device=\(String(describing: device), privacy: .public), restore=\(String(describing: AppDelegate.restoreOrientation), privacy: .public)")

        AppDelegate.orientationLock = .landscape
        AppDelegate.rotate(to: .landscape)
    }

    private func deactivate() {
        AppDelegate.log.info("deactivate (onDisappear) fired")
        // Rotation is restored in CardListView after the dismissal completes;
        // a request made here would race the dismissal transition.
        UIApplication.shared.isIdleTimerDisabled = false
        // If the one-off max-brightness toggle was still active, restore the
        // brightness it overrode.
        if let saved = savedBrightness {
            screen.brightness = saved
            savedBrightness = nil
        }
    }
}
