//Utilities
// helper functions

import Foundation
import UIKit
import SwiftUI

struct Utilities {
    private static let lastBundleModificationDateKey = "lastBundleModificationDate"

    static func isFirstLaunchForNewBuild() -> Bool {
        if getppid() != 1 { return true }
        let currentModificationDate = getBundleModificationDate()
        let storedModificationDate = UserDefaults.standard.object(forKey: lastBundleModificationDateKey) as? Date
        let isNewBuild = (storedModificationDate == nil || storedModificationDate != currentModificationDate)
        print("Checking bundle modification date. Current: \(currentModificationDate ?? Date()), Stored: \(storedModificationDate ?? Date())")
        return isNewBuild
    }

    static func getBundleModificationDate() -> Date? {
        if let infoPlistURL = Bundle.main.url(forResource: "Info", withExtension: "plist"),
           let attributes = try? FileManager.default.attributesOfItem(atPath: infoPlistURL.path),
           let modificationDate = attributes[.modificationDate] as? Date {
            print("Bundle modification date: \(modificationDate)")
            return modificationDate
        }
        return nil
    }

    static func updateStoredModificationDate() {
        if let currentModificationDate = getBundleModificationDate() {
            UserDefaults.standard.set(currentModificationDate, forKey: lastBundleModificationDateKey)
            UserDefaults.standard.synchronize()
            print("Updated stored bundle modification date to \(currentModificationDate).")
        }
    }

    static func restart() {
        AppLoadTracker.hasRestarted = true // Set the restart flag

        guard let window = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            return
        }
        
        // Reset the root view controller to a fresh instance of ContentView
        window.windows.first?.rootViewController = UIHostingController(rootView: MainView())
        window.windows.first?.makeKeyAndVisible()
    }
}



struct AppLoadTracker {
    private static let hasRestartedKey = "hasRestarted"

    static var hasRestarted: Bool {
        get {
            return UserDefaults.standard.bool(forKey: hasRestartedKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: hasRestartedKey)
        }
    }
}
