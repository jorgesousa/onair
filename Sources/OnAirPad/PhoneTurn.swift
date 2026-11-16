import SwiftUI
import UIKit

/// The iPhone side of `FullScreenTurn`: which orientations the app allows right now, and the
/// request that turns the screen. Released once the phone is physically held that way.
@MainActor
final class PhoneTurn: NSObject, UIApplicationDelegate {
    static private(set) var lockedTo: FullScreenTurn.Way?
    private static var observer: NSObjectProtocol?

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        switch Self.lockedTo {
        case .landscape: return .landscape
        case .portrait: return .portrait
        case nil: return UIDevice.current.userInterfaceIdiom == .phone ? .allButUpsideDown : .all
        }
    }

    static func turn(to way: FullScreenTurn.Way) {
        lockedTo = way
        watchDevice()
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: way == .landscape ? .landscapeRight : .portrait))
    }

    private static func watchDevice() {
        guard observer == nil else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        observer = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                                          object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let o = UIDevice.current.orientation
                let held: FullScreenTurn.Way? = o.isLandscape ? .landscape : (o == .portrait ? .portrait : nil)
                guard FullScreenTurn.release(lockedTo: lockedTo, held: held) else { return }
                lockedTo = nil
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?
                    .keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }
}
