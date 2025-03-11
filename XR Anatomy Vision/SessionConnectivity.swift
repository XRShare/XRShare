import Foundation
import RealityKit
import SwiftUI

/// Handles session connectivity and synchronization for models in the scene
class SessionConnectivity: ObservableObject {
    
    /// Track which entities have been registered for synchronization
    private var registeredEntities = Set<Entity.ID>()
    
    /// Add essential anchors to the RealityView content
    func addAnchorsIfNeeded(
        headAnchor: AnchorEntity,
        modelAnchor: AnchorEntity,
        content: RealityViewContent
    ) {
        // Make sure we only add these anchors once
        if !content.entities.contains(where: { $0.id == headAnchor.id }) {
            content.add(headAnchor)
        }
        
        if !content.entities.contains(where: { $0.id == modelAnchor.id }) {
            content.add(modelAnchor)
        }
    }
    
    /// Broadcast transform changes if needed
    func broadcastTransformIfNeeded(entity: Entity, arViewModel: ARViewModel) {
        // Register the entity for synchronization if not already done
        if !registeredEntities.contains(entity.id) {
            if let modelTypeComponent = entity.components[ModelTypeComponent.self] {
                // Register with model type
                arViewModel.customService?.registerEntity(
                    entity,
                    modelType: modelTypeComponent.type,
                    ownedByLocalPeer: true
                )
            } else {
                // Register without model type
                arViewModel.customService?.registerEntity(entity, ownedByLocalPeer: true)
            }
            registeredEntities.insert(entity.id)
        }
        
        // Send transform update
        arViewModel.sendTransform(for: entity)
    }
    
    /// Reset all tracking
    func reset() {
        registeredEntities.removeAll()
    }
    
    func broadcastAnchorCreation(_ anchorEntity: AnchorEntity, modelType: ModelType? = nil) {
        let transformArr = anchorEntity.transform.matrix.toArray()
        let modelID = modelType?.rawValue ?? "anchor-\(UUID())"
        let payload = AnchorTransformPayload(
            anchorData: Data(),
            modelID: modelID,
            transform: transformArr,
            modelType: modelType?.rawValue
        )
        // ...
    }
    
    private func setupTransformObserver(for entity: ModelEntity) {
        entity.transform.observe { [weak self] transform in
            guard let self = self,
                  !self.isApplyingRemoteTransform, // Skip if applying remote transform
                  let arViewModel = self.arViewModel else { return }
            
            // Only broadcast if the change is significant
            let currentMatrix = transform.matrix
            if let lastMatrix = entity.components[LastTransformComponent.self]?.matrix,
               !simd_almost_equal_elements(currentMatrix, lastMatrix, 0.0001) {
                arViewModel.sendTransform(for: entity)
            }
            
            // Update the last known transform
            entity.components[LastTransformComponent.self] = LastTransformComponent(matrix: currentMatrix)
        }
    }
    
    private var isApplyingRemoteTransform = false

    func applyRemoteTransform(_ matrix: simd_float4x4, to entity: Entity) {
    } 
}
