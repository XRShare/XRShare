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
        // This forces the device to use the given orientation.
        UIDevice.current.setValue(orientation == .portrait ? UIInterfaceOrientation.portrait.rawValue : UIInterfaceOrientation.unknown.rawValue, forKey: "orientation")
    }

    func unlock() {
        lock(to: .all)
    }
}