//
//  Utilities.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-14.
//


import Foundation
import SwiftUI
import UIKit

// MARK: - Logging Configuration
struct Logger {
    #if DEBUG
    static let isEnabled = true
    #else
    static let isEnabled = false
    #endif
    
    static func log(_ message: String, category: LogCategory = .general) {
        guard isEnabled else { return }
        print("[\(category.rawValue)] \(message)")
    }
    
    enum LogCategory: String {
        case general = "General"
        case networking = "Network"
        case ar = "AR"
        case model = "Model"
        case sync = "Sync"
        case gesture = "Gesture"
        case debug = "Debug"
    }
}

/// Utility functions for app functionality
class Utilities {
    // UserDefaults keys
    private static let lastBuildVersionKey = "LastBuildVersion"
    private static let lastUpdateDateKey = "LastUpdateDate"
    private static let hasCompletedFirstLaunchKey = "HasCompletedFirstLaunch"
    
    /// The current app build version
    private static var currentBuildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1.0.0"
    }
    
    /// Check if this is the first launch after a new build was installed
    static func isFirstLaunchForNewBuild() -> Bool {
        let defaults = UserDefaults.standard
        
        // Get the last saved build version
        let lastBuildVersion = defaults.string(forKey: lastBuildVersionKey)
        
        // First run check
        if lastBuildVersion == nil {
            print("First ever app launch detected")
            // Store the current build version immediately
            defaults.set(currentBuildVersion, forKey: lastBuildVersionKey)
            return true
        }
        
        // Check if this is a new build
        if lastBuildVersion != currentBuildVersion {
            print("New build detected: Previous=\(lastBuildVersion ?? "nil"), Current=\(currentBuildVersion)")
            // Update to the current build version
            defaults.set(currentBuildVersion, forKey: lastBuildVersionKey)
            // Reset first launch completion flag for new build
            defaults.set(false, forKey: hasCompletedFirstLaunchKey)
            return true
        }
        
        // Check if we've completed the first launch sequence for this build
        let hasCompletedFirstLaunch = defaults.bool(forKey: hasCompletedFirstLaunchKey)
        if !hasCompletedFirstLaunch {
            return true
        }
        
        return false
    }
    
    /// Mark the app as having completed the first launch sequence
    static func markFirstLaunchComplete() {
        UserDefaults.standard.set(true, forKey: hasCompletedFirstLaunchKey)
    }
    
    /// Update the stored modification date (e.g. after loading models)
    static func updateStoredModificationDate() {
        let currentDate = Date().timeIntervalSince1970
        UserDefaults.standard.set(currentDate, forKey: lastUpdateDateKey)
        // Also mark first launch as complete
        markFirstLaunchComplete()
    }
    
    /// Reset all app settings and storage
    static func resetAllSettings() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: lastBuildVersionKey)
        defaults.removeObject(forKey: lastUpdateDateKey)
        defaults.removeObject(forKey: hasCompletedFirstLaunchKey)
        
        // Force defaults to sync
        defaults.synchronize()
        
        print("All app settings have been reset")
    }
    
    static func restart() {
        AppLoadTracker.hasRestarted = true
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let _ = scene.windows.first
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
