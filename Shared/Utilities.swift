//
//  Utilities.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-14.
//


import Foundation
import SwiftUI
import UIKit

struct Utilities {
    private static let lastBundleModificationDateKey = "lastBundleModificationDate"
    
    
    static func isFirstLaunchForNewBuild() -> Bool {
        let currentDate = getBundleModificationDate()
        let storedDate = UserDefaults.standard.object(forKey: lastBundleModificationDateKey) as? Date
        return (storedDate == nil || storedDate != currentDate)
    }
    
    static func getBundleModificationDate() -> Date? {
        guard let url = Bundle.main.url(forResource: "Info", withExtension: "plist"),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date
        else { return nil }
        return modDate
    }
    
    static func updateStoredModificationDate() {
        if let date = getBundleModificationDate() {
            UserDefaults.standard.set(date, forKey: lastBundleModificationDateKey)
        }
    }
    
    static func restart() {
        AppLoadTracker.hasRestarted = true
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first
        else { return }
//        #if os(visionOS)
//        window.rootViewController = UIHostingController(rootView: ContentView(modelManager: modelManager))
//        window.makeKeyAndVisible()
//        #endif

    }
}

struct AppLoadTracker {
    private static let hasRestartedKey = "hasRestarted"
    static var hasRestarted: Bool {
        get { UserDefaults.standard.bool(forKey: hasRestartedKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasRestartedKey) }
    }
}
