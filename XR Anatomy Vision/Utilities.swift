import Foundation
import SwiftUI

struct Utilities {
    // Same logic or minimal for a Vision Pro environment
}

struct AppLoadTracker {
    private static let hasRestartedKey = "hasRestarted"

    static var hasRestarted: Bool {
        get { UserDefaults.standard.bool(forKey: hasRestartedKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasRestartedKey) }
    }
}
