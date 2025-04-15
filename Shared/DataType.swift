//
//  DataType.swift
//  XR Anatomy
//
//  Created by ...
//

import Foundation

enum DataType: UInt8, Codable {
    case arWorldMap = 0
    case anchor = 1
    case collaborationData = 2
    case modelTransform = 3
    case removeAnchors = 4
    
    /// We'll use this one to send anchor + transform in one go.
    case anchorWithTransform = 5
    
    case permissionUpdate = 6
    case textMessage = 7
    
    // Synchronization for model add/remove
    case addModel = 8
    case removeModel = 9
    
    // Simple test message
    case testMessage = 10
    
    // Add others if needed...
}
