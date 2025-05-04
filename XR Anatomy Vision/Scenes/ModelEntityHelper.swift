//
//  ModelEntityHelper.swift
//  XR Anatomy Vision
//
//  Created by Joanna  Lin  on 2025-04-21.
//

import Foundation
import RealityKit

extension ModelEntity {
    func addTappable() -> ModelEntity{
        let newModelEntity = self.clone(recursive: true)
        
        
        // Need this to recieve input inside realityView (tapping gesture)
        newModelEntity.components.set(InputTargetComponent())
        
        // Need concreate shape to locate where the tapping action is happening
        newModelEntity.generateCollisionShapes(recursive: true)
        return newModelEntity
        
    }
}
