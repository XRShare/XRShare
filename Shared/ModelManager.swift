import SwiftUI
import RealityKit
import UIKit

/// Manages placed models, gestures, and related logic
final class ModelManager: ObservableObject {
    @Published var placedModels: [Model] = []
    @Published var modelDict: [Entity: Model] = [:]
    @Published var entityInitialRotations: [Entity: simd_quatf] = [:]
    @Published var modelTypes: [ModelType] = []
    @Published var selectedModelID: ModelType? = nil

    var transformCache = TransformCache()
    
    init() {
        loadModelTypes()
    }

    func loadModelTypes() {
        self.modelTypes = ModelType.allCases()
        print("Loaded model types: \(modelTypes.map { $0.rawValue })")
    }

    // MARK: - Loading a ModelEntity
    func loadModel(for modelType: ModelType, arViewModel: ARViewModel?) {
        Task {
            print("Attempting to load model: \(modelType.rawValue).usdz")
            let model = await Model.load(modelType: modelType, arViewModel: arViewModel)
            let modelEntity = await MainActor.run { model.modelEntity }
            if let entity = modelEntity {
                await MainActor.run {
                    self.modelDict[entity] = model
                    self.placedModels.append(model)
                    
                    // Automatically select newly loaded model
                    self.selectedModelID = modelType
                }
                // Add await here to fix visionOS build error
                let customService = await MainActor.run { arViewModel?.customService }
                if let customService = customService {
                    customService.registerEntity(entity, modelType: modelType)
                }
                
                // Broadcast the addition of this model instance
                if let arViewModel = arViewModel, let _ = arViewModel.customService {
                    // Use InstanceIDComponent for a stable ID across sessions if available
                    let instanceID = entity.components[InstanceIDComponent.self]?.id ?? entity.id.stringValue
                    
                    // Determine the transform based on sync mode
                    let transformMatrix: simd_float4x4
                    let isRelativeToImageAnchor: Bool
                    
                    if arViewModel.currentSyncMode == .imageTarget {
                        // Send transform relative to the shared image anchor
                        transformMatrix = entity.transformMatrix(relativeTo: arViewModel.sharedAnchorEntity)
                        isRelativeToImageAnchor = true
                    } else {
                        // Send world transform
                        transformMatrix = entity.transform.matrix
                        isRelativeToImageAnchor = false
                    }
                    
                    let transformArray = transformMatrix.toArray()
                    
                    let payload = AddModelPayload(
                        instanceID: instanceID,
                        modelType: modelType.rawValue,
                        transform: transformArray,
                        isRelativeToImageAnchor: isRelativeToImageAnchor // Send relative flag
                    )
                    do {
                        let data = try JSONEncoder().encode(payload)
                        arViewModel.multipeerSession?.sendToAllPeers(data, dataType: .addModel)
                        print("Broadcasted addModel: \(modelType.rawValue) (ID: \(instanceID)), Relative: \(isRelativeToImageAnchor)")
                    } catch {
                        print("Error encoding AddModelPayload: \(error)")
                    }
                }
                
                print("\(modelType.rawValue) chosen – model loaded and selected")
            } else {
                print("Failed to load model entity for \(modelType.rawValue).usdz")
            }
        }
    }

    // MARK: - Remove a Single Model
    @MainActor func removeModel(_ model: Model, broadcast: Bool = true) { // Added broadcast flag
        guard let entity = model.modelEntity else { return }
        // Use InstanceIDComponent for removal broadcast if available
        let instanceID = entity.components[InstanceIDComponent.self]?.id ?? entity.id.stringValue
        let modelTypeName = model.modelType.rawValue // Get name before potential removal
        
        // Broadcast removal *before* removing locally
        if broadcast, let arViewModel = model.arViewModel, let _ = arViewModel.customService {
            let payload = RemoveModelPayload(instanceID: instanceID)
            do {
                let data = try JSONEncoder().encode(payload)
                arViewModel.multipeerSession?.sendToAllPeers(data, dataType: .removeModel)
                print("Broadcasted removeModel: \(modelTypeName) (ID: \(instanceID))")
            } catch {
                print("Error encoding RemoveModelPayload: \(error)")
            }
        }
        
        // Clean up entity properly
        // Remove any highlight entities first
        if let highlight = entity.findEntity(named: "selectionHighlight") {
            highlight.removeFromParent()
        }
        
        // Clear components that might cause networking issues
        if entity.components[SelectionComponent.self] != nil {
            entity.components.remove(SelectionComponent.self)
        }
        
        // Unregister from connectivity service before removing from parent
        if let arViewModel = model.arViewModel, let customService = arViewModel.customService {
             customService.unregisterEntity(entity)
        }
        
        // Remove from parent after cleanup
        entity.removeFromParent()
        
        // Update collections
        placedModels.removeAll { $0.id == model.id }
        modelDict = modelDict.filter { $0.value.id != model.id }
        
        // If we removed the selected model, select another model if available
        if selectedModelID == model.modelType {
            selectedModelID = placedModels.first?.modelType
        }
        
        print("Removed model: \(model.modelType.rawValue)")
    }
    
    @MainActor func reset() {
        // Clean up entities properly before removing
        placedModels.forEach { model in
            if let entity = model.modelEntity {
                // Remove highlights first
                if let highlight = entity.findEntity(named: "selectionHighlight") {
                    highlight.removeFromParent()
                }
                
                // Clear components
                if entity.components[SelectionComponent.self] != nil {
                    entity.components.remove(SelectionComponent.self)
                }
                
                // Unregister from connectivity service
                if let arViewModel = model.arViewModel, let customService = arViewModel.customService {
                     customService.unregisterEntity(entity)
                }

                // Remove from parent last
                entity.removeFromParent()
            }
        }
        
        // Clear all collections
        placedModels.removeAll()
        modelDict.removeAll()
        entityInitialRotations.removeAll()
        transformCache.lastTransforms.removeAll()
        selectedModelID = nil
        print("Reset ModelManager state.")
    }
    
    // MARK: - Update the 3D Scene (visionOS specific logic removed/adjusted for shared context)
    @MainActor func updatePlacedModels(
        // Parameters adjusted for broader use, RealityViewContent specific parts removed
        // content: RealityViewContent, // Removed
        // modelAnchor: AnchorEntity, // Removed - handled by ARViewModel/platform
        // connectivity: SessionConnectivity, // Removed - handled by ARViewModel/platform
        arViewModel: ARViewModel
    ) {
        // Choose which anchor to use based on the current sync mode
        let anchorToUse: Entity = arViewModel.currentSyncMode == .imageTarget ?
                           arViewModel.sharedAnchorEntity : Entity() // Use simple Entity() as placeholder for world-space

        // Ensure the shared anchor is in the scene if using image target mode
        if arViewModel.currentSyncMode == .imageTarget && arViewModel.sharedAnchorEntity.scene == nil {
             arViewModel.currentScene?.addAnchor(arViewModel.sharedAnchorEntity)
             print("Added missing sharedAnchorEntity to scene for image target mode.")
        }

        // Check all models
        for model in placedModels {
            guard let entity = model.modelEntity else { continue }
            
            // Make sure entity is visible
            entity.isEnabled = true
            
            // If entity has no parent, add it to the appropriate anchor/scene
            if entity.parent == nil {
                if arViewModel.currentSyncMode == .imageTarget {
                    // Add to shared image anchor
                    if arViewModel.sharedAnchorEntity.scene != nil {
                        arViewModel.sharedAnchorEntity.addChild(entity)
                        print("Added \(entity.name) to sharedAnchorEntity.")
                    } else {
                        print("Warning: Cannot add \(entity.name) to sharedAnchorEntity, it's not in the scene.")
                        // Optionally add to scene root as fallback?
                        // arViewModel.currentScene?.addAnchor(AnchorEntity(world: entity.transform.matrix)) // Example fallback
                    }
                } else {
                    // Add to world space (using an AnchorEntity on iOS, or directly if possible on visionOS - handled by RealityView)
                    #if os(iOS)
                    if let scene = arViewModel.currentScene {
                        let worldAnchor = AnchorEntity(world: entity.transform.matrix)
                        worldAnchor.addChild(entity)
                        scene.addAnchor(worldAnchor) // Add anchor to the ARView scene
                        print("Added \(entity.name) to world anchor in iOS scene.")
                    }
                    #elseif os(visionOS)
                    // On visionOS, RealityView manages adding entities. We assume it's handled.
                    // If we need a specific anchor, it should be added in the RealityView setup.
                    // For now, just log. If it needs explicit adding, it depends on the RealityView structure.
                    print("Assuming \(entity.name) is added to the scene by RealityView in visionOS world mode.")
                    // Example: If a specific 'modelAnchor' exists in RealityView:
                    // if let modelAnchor = arViewModel.currentScene?.findEntity(named: "modelAnchor") {
                    //     modelAnchor.addChild(entity)
                    // }
                    #endif
                }
                
                // Set initial position/scale if just added
                entity.setPosition([0, 0.1, -0.5], relativeTo: nil) // Position relative to world origin initially
                model.position = entity.position
                
                // Apply model-specific scaling
                if model.modelType.rawValue.lowercased() == "pancakes" {
                    entity.scale = SIMD3<Float>(repeating: 0.08)
                } else if model.modelType.rawValue.lowercased() == "heart" ||
                          model.modelType.rawValue.lowercased() == "arterieshead" {
                    entity.scale = SIMD3<Float>(repeating: 0.2)
                } else {
                    entity.scale = SIMD3<Float>(repeating: 0.15)
                }
                model.scale = entity.scale
                print("Positioned \(entity.name) at \(entity.position) with scale \(entity.scale)")
            }
            
            // Visual highlight for selected model (logic remains the same)
            if model.modelType == selectedModelID {
                if entity.components[SelectionComponent.self] == nil {
                    entity.components.set(SelectionComponent())
                    if entity.findEntity(named: "selectionHighlight") == nil {
                        let bounds = entity.visualBounds(relativeTo: nil)
                        let highlightSize = bounds.extents * 1.05
                        let boxMaterial = SimpleMaterial(color: UIColor.blue.withAlphaComponent(0.2), roughness: 0.5, isMetallic: false)
                        let boxMesh = MeshResource.generateBox(size: highlightSize, cornerRadius: 0.01)
                        let highlightEntity = ModelEntity(mesh: boxMesh, materials: [boxMaterial])
                        highlightEntity.name = "selectionHighlight"
                        highlightEntity.position = SIMD3<Float>(0, 0, 0)
                        entity.addChild(highlightEntity)
                    }
                    print("Added selection highlight to \(model.modelType.rawValue)")
                }
            } else {
                if entity.components[SelectionComponent.self] != nil {
                    entity.components.remove(SelectionComponent.self)
                    if let highlightEntity = entity.findEntity(named: "selectionHighlight") {
                        highlightEntity.removeFromParent()
                        print("Removed selection highlight from \(model.modelType.rawValue)")
                    }
                }
            }
            
            // Check for transform changes; broadcast if changed
            // Determine the relevant transform based on sync mode
            let currentMatrix: simd_float4x4
            if arViewModel.currentSyncMode == .imageTarget && arViewModel.sharedAnchorEntity.scene != nil {
                 // Get transform relative to the image anchor
                 currentMatrix = entity.transformMatrix(relativeTo: arViewModel.sharedAnchorEntity)
            } else {
                 // Get world transform
                 currentMatrix = entity.transform.matrix
            }

            let entityID = entity.id
            if let lastMatrix = transformCache.lastTransforms[entityID],
               !simd_almost_equal_elements(currentMatrix, lastMatrix, 0.0001) { // Use helper for comparison
                // Transform changed, broadcast it
                arViewModel.sendTransform(for: entity) // Use ARViewModel's method which handles sync mode
                self.transformCache.lastTransforms[entityID] = currentMatrix // Update cache
            } else if transformCache.lastTransforms[entityID] == nil {
                // First time seeing this entity, cache its transform
                self.transformCache.lastTransforms[entityID] = currentMatrix
            }
        }
    }

    // MARK: - Gestures (Platform Agnostic - Requires platform-specific setup)

    // Note: The gesture implementations below are conceptual for the shared ModelManager.
    // The actual gesture recognizers need to be added in the platform-specific views
    // (e.g., ARViewContainer for iOS, RealityView for visionOS) and trigger these methods.

    // --- Gesture Handling Methods (to be called by platform views) ---

    @MainActor func handleTap(entity: Entity) {
        let name = entity.name.isEmpty ? "unnamed entity" : entity.name
        if let model = self.modelDict[entity] {
            self.selectedModelID = model.modelType
            entity.isEnabled = true
            if let parent = entity.parent { parent.isEnabled = true }
            print("🎯 SELECT: Tapped \(name) - now selected")
        } else {
            print("ℹ️ Tapped non-model entity: \(name)")
        }
    }

    @MainActor func handleDragChange(entity: Entity, translation: SIMD3<Float>, arViewModel: ARViewModel) {
        let name = entity.name.isEmpty ? "unnamed entity" : entity.name
        
        // Apply dampened and clamped delta
        let delta = translation * 0.001 // Adjust sensitivity as needed
        let smoothedDelta = SIMD3<Float>(
            min(max(delta.x, -0.01), 0.01),
            min(max(delta.y, -0.01), 0.01),
            min(max(delta.z, -0.01), 0.01)
        )
        
        let oldPosition = entity.position(relativeTo: nil) // Get world position
        
        // Apply position change in world space
        entity.setPosition(oldPosition + smoothedDelta, relativeTo: nil)
        
        if let model = self.modelDict[entity] {
            model.position = entity.position // Update local model state if needed
            self.selectedModelID = model.modelType // Select on interaction
            arViewModel.sendTransform(for: entity) // Send update
        }
        
        // print("🔵 DRAG: \(name) to world pos \(entity.position(relativeTo: nil))")
    }

    @MainActor func handleDragEnd(entity: Entity, arViewModel: ARViewModel) {
        if let model = self.modelDict[entity] {
            model.position = entity.position // Final update to local model state
            self.selectedModelID = model.modelType
            arViewModel.sendTransform(for: entity) // Send final update
        }
        print("✅ Drag gesture ended for \(entity.name)")
    }

    @MainActor func handleScaleChange(entity: Entity, scaleFactor: Float, arViewModel: ARViewModel) {
        let name = entity.name.isEmpty ? "unnamed entity" : entity.name
        
        // Apply dampened scale factor
        let dampedScaleFactor = 1.0 + (scaleFactor - 1.0) * 0.1 // Adjust sensitivity
        let currentScale = entity.scale
        var newScale = currentScale * dampedScaleFactor
        
        // Clamp scale
        let minScale: Float = 0.02
        let maxScale: Float = 2.0
        newScale = simd_clamp(newScale, SIMD3<Float>(repeating: minScale), SIMD3<Float>(repeating: maxScale))
        
        entity.scale = newScale
        
        if let model = self.modelDict[entity] {
            model.scale = entity.scale
            self.selectedModelID = model.modelType
            arViewModel.sendTransform(for: entity)
        }
        // print("🔍 SCALE: \(name) to \(entity.scale)")
    }

    @MainActor func handleScaleEnd(entity: Entity, arViewModel: ARViewModel) {
        if let model = self.modelDict[entity] {
            model.scale = entity.scale
            model.updateCollisionBox() // Update collision after scaling
            self.selectedModelID = model.modelType
            arViewModel.sendTransform(for: entity)
        }
        print("✅ Scale gesture ended for \(entity.name) at \(entity.scale)")
    }

    @MainActor func handleRotationChange(entity: Entity, rotation: simd_quatf, arViewModel: ARViewModel) {
        let name = entity.name.isEmpty ? "unnamed entity" : entity.name

        // Apply dampened rotation directly (relative to current orientation)
        // Decompose the input rotation to get angle and axis
        let angle = rotation.angle * 0.1 // Dampen sensitivity
        let axis = rotation.axis
        
        let deltaRotation = simd_quatf(angle: angle, axis: axis)
        
        // Combine with current rotation
        entity.transform.rotation = entity.transform.rotation * deltaRotation
        
        if let model = self.modelDict[entity] {
            model.rotation = entity.transform.rotation
            self.selectedModelID = model.modelType
            arViewModel.sendTransform(for: entity)
        }
        // print("🔄 ROTATE: \(name) by angle \(angle)")
    }

    @MainActor func handleRotationEnd(entity: Entity, arViewModel: ARViewModel) {
        if let model = self.modelDict[entity] {
            model.rotation = entity.transform.rotation
            self.selectedModelID = model.modelType
            arViewModel.sendTransform(for: entity)
        }
        // Clean up initial rotation cache if used
        self.entityInitialRotations.removeValue(forKey: entity)
        print("✅ Rotation gesture ended for \(entity.name)")
    }
    
    // --- Placeholder Gestures for visionOS (Actual gestures attached in RealityView) ---
    #if os(visionOS)
    // These properties are placeholders; the actual gestures are defined and attached
    // within the `InSession` RealityView in the visionOS target.
    var tapGesture: some Gesture { SpatialTapGesture().onEnded { _ in } }
    var dragGesture: some Gesture { DragGesture().onChanged { _ in }.onEnded { _ in } }
    var scaleGesture: some Gesture { MagnifyGesture().onChanged { _ in }.onEnded { _ in } }
    var rotationGesture: some Gesture { RotateGesture().onChanged { _ in }.onEnded { _ in } }
    #endif
}

// Helper function for clamping SIMD vectors (if not available)
func simd_clamp<T: SIMD>(_ vector: T, _ minVec: T, _ maxVec: T) -> T where T.Scalar: FloatingPoint {
    var result = T()
    for i in 0..<vector.scalarCount {
        result[i] = max(minVec[i], min(vector[i], maxVec[i]))
    }
    return result
}