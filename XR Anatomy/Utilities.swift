import Foundation
import UIKit
import SwiftUI

struct Utilities {
    private static let lastBundleModificationDateKey = "lastBundleModificationDate"

    static func isFirstLaunchForNewBuild() -> Bool {
        if getppid() != 1 { return true }
        let currentDate = getBundleModificationDate()
        let storedDate = UserDefaults.standard.object(forKey: lastBundleModificationDateKey) as? Date
        return (storedDate == nil || storedDate != currentDate)
    }

    static func getBundleModificationDate() -> Date? {
        guard let url = Bundle.main.url(forResource: "Info", withExtension: "plist") else { return nil }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modDate = attrs[.modificationDate] as? Date {
            return modDate
        }
        return nil
    }

    static func updateStoredModificationDate() {
        if let date = getBundleModificationDate() {
            UserDefaults.standard.set(date, forKey: lastBundleModificationDateKey)
            UserDefaults.standard.synchronize()
        }
    }

    static func restart() {
        AppLoadTracker.hasRestarted = true
        guard let wscene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        wscene.windows.first?.rootViewController = UIHostingController(rootView: UIView())
        wscene.windows.first?.makeKeyAndVisible()
    }
}

struct AppLoadTracker {
    private static let hasRestartedKey = "hasRestarted"
    static var hasRestarted: Bool {
        get { UserDefaults.standard.bool(forKey: hasRestartedKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasRestartedKey) }
    }
}

class OrientationManager {
    static let shared = OrientationManager()
    private init() {}
    var orientationLock: UIInterfaceOrientationMask = .all

    func lock(to orientation: UIInterfaceOrientationMask) {
        orientationLock = orientation
        UIDevice.current.setValue(
            orientation == .portrait ? UIInterfaceOrientation.portrait.rawValue : UIInterfaceOrientation.unknown.rawValue,
            forKey: "orientation"
        )
    }

    func unlock() {
        lock(to: .all)
    }
}

class PortraitHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }
    override var shouldAutorotate: Bool { false }
}

struct PortraitLockedView<Content: View>: UIViewControllerRepresentable {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    func makeUIViewController(context: Context) -> UIViewController {
        PortraitHostingController(rootView: content)
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
