//
//  OrientationManager.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-14.
//


import UIKit

class OrientationManager {
    static let shared = OrientationManager()
    private init() {}
    
    var orientationLock: UIInterfaceOrientationMask = .all

    func lock(to orientation: UIInterfaceOrientationMask) {
        orientationLock = orientation
        // Note: UIDevice.setValue for orientation is deprecated
        // The actual orientation locking is handled in the AppDelegate's supportedInterfaceOrientations
    }

    func unlock() {
        lock(to: .all)
    }
}