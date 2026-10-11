import OSLog
import SwiftData
import SwiftUI

/// Orientation lock used by presentation mode: the app delegate reports the
/// mask, and the presentation view requests geometry updates on enter/exit.
/// The restore request is issued from fullScreenCover's `onDismiss` — i.e.
/// after the dismissal transition — because iOS drops geometry requests made
/// mid-transition.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .all

    /// Orientation the list should return to after presentation mode
    /// (captured when presentation mode is entered).
    static var restoreOrientation: UIInterfaceOrientationMask = .portrait

    static let log = Logger(subsystem: "dev.barcodedeck.app", category: "rotation")

    /// Requests a scene rotation, retrying every 150 ms (up to ~2 s) until
    /// UIKit accepts it. Requests made during view-controller transitions are
    /// rejected with error 101, so a single call is unreliable at both entry
    /// and exit of presentation mode.
    ///
    /// The first request is deferred by one runloop tick: the supported-
    /// orientation invalidation below is only *processed* on the next update
    /// pass, and requesting earlier makes UIKit validate the geometry update
    /// against the stale mask (error 101) every single time.
    static func rotate(to mask: UIInterfaceOrientationMask) {
        log.info("rotate → \(String(describing: mask), privacy: .public)")
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene })
            as? UIWindowScene
        else { return }

        scene.keyWindow?.rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()

        DispatchQueue.main.async {
            attempt(scene, mask, 1)
        }
    }

    private static func attempt(_ scene: UIWindowScene, _ mask: UIInterfaceOrientationMask, _ n: Int) {
        scene.requestGeometryUpdate(
            .iOS(interfaceOrientations: mask),
            errorHandler: { error in
                log.debug("rotate attempt \(n) rejected (will retry): \(String(describing: error), privacy: .public)")
                guard n < 12 else {
                    log.error("rotate gave up after \(n) attempts")
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    attempt(scene, mask, n + 1)
                }
            }
        )
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }
}

@main
struct BarcodeDeckApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            CardListView()
        }
        .modelContainer(for: Card.self)
    }
}
