import Foundation
import RealityKit
import SwiftUI
import Combine

/// Handles session connectivity and synchronization for models in the scene
class SessionConnectivity: ObservableObject {
    
    /// Track which entities have been registered for synchronization
    private var registeredEntities = Set<Entity.ID>()
    private var transformCancellables = [AnyCancellable]()
    
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
        
        // Send transform update with respect to the appropriate anchor
        // depending on the current sync mode
        arViewModel.sendTransform(for: entity)
    }
    
    /// Reset all tracking
    func reset() {
        registeredEntities.removeAll()
        transformCancellables.forEach { $0.cancel() }
        transformCancellables.removeAll()
    }
    
    func broadcastAnchorCreation(_ anchorEntity: AnchorEntity, modelType: ModelType? = nil) {
        let transformArr = anchorEntity.transform.matrix.toArray()
        let modelID = modelType?.rawValue ?? "anchor-\(UUID())"
        _ = AnchorTransformPayload(
            anchorData: Data(),
            anchorID: modelID,
            transform: transformArr,
            modelType: modelType?.rawValue
        )
        // ...
    }
    
    private func setupTransformObserver(for entity: ModelEntity, arViewModel: ARViewModel) {
        // Ensure the entity is part of a scene
        guard let scene = entity.scene else {
            // If the entity is not attached to a scene, we cannot observe updates
            return
        }

        let cancellable = scene.subscribe(to: SceneEvents.Update.self) { [weak self] (event: SceneEvents.Update) in
            guard let self = self, !self.isApplyingRemoteTransform else { return }

            // Retrieve the current transform from the entity
            let newTransform: Transform = entity.transform
            let currentMatrix = newTransform.matrix
            
            // Check if the transform has changed significantly
            if let lastMatrix = entity.components[LastTransformComponent.self]?.matrix,
               !simd_almost_equal_elements(currentMatrix, lastMatrix, 0.0001) {
                arViewModel.sendTransform(for: entity)
            }

            // Update the last known transform component
            entity.components[LastTransformComponent.self] = LastTransformComponent(matrix: currentMatrix)
        }
        transformCancellables.append(cancellable as! AnyCancellable)
    }
    
    private var isApplyingRemoteTransform = false

    func applyRemoteTransform(_ matrix: simd_float4x4, to entity: Entity) {
    }
}
