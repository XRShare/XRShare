// not normally used in a SwiftUI project, but using this for the orientationLock feature used in the start menu... SwiftUI's locks do not work well.

import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        // Lock orientation as needed (or .all if you want full rotation)
        return OrientationManager.shared.orientationLock
    }
}
