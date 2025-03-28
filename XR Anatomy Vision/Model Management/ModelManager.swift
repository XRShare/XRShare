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
                let customService = await MainActor.run { arViewModel?.currentScene?.synchronizationService }
                if let customService = customService as? MyCustomConnectivityService {
                    customService.registerEntity(entity, modelType: modelType)
                }
                
                // Broadcast the addition of this model instance
                if let arViewModel = arViewModel, let _ = arViewModel.customService {
                    let instanceID = entity.id.stringValue // Use entity ID as unique instance ID
                    let transformArray = entity.transform.matrix.toArray()
                    let payload = AddModelPayload(
                        instanceID: instanceID,
                        modelType: modelType.rawValue,
                        transform: transformArray,
                        isRelativeToImageAnchor: arViewModel.currentSyncMode == .imageTarget // Send relative flag
                    )
                    do {
                        let data = try JSONEncoder().encode(payload)
                        arViewModel.multipeerSession?.sendToAllPeers(data, dataType: .addModel)
                        print("Broadcasted addModel: \(modelType.rawValue) (ID: \(instanceID))")
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
        let instanceID = entity.id.stringValue // Get ID before potential removal
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
            // Remove highlights first to avoid unbound component errors
            if let entity = model.modelEntity {
                // Remove any highlight entities first
                if let highlight = entity.findEntity(named: "selectionHighlight") {
                    highlight.removeFromParent()
                }
                
                // Clear components that might cause networking issues
                if entity.components[SelectionComponent.self] != nil {
                    entity.components.remove(SelectionComponent.self)
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
    }
    
    // MARK: - Update the 3D Scene
    @MainActor func updatePlacedModels(
        content: RealityViewContent,
        modelAnchor: AnchorEntity,
        connectivity: SessionConnectivity,
        arViewModel: ARViewModel
    ) {
        // SIMPLIFIED APPROACH - REVERT TO ORIGINAL WORKING VERSION
        
        // Choose which anchor to use based on the current sync mode
        let anchorToUse = arViewModel.currentSyncMode == .imageTarget ?
                           arViewModel.sharedAnchorEntity : modelAnchor
        
        // Log which anchor we're using
        print("Using \(arViewModel.currentSyncMode == .imageTarget ? "image target" : "world") anchor mode")
        
        // Make sure both anchors are in the scene
        if modelAnchor.parent == nil && !content.entities.contains(where: { $0.id == modelAnchor.id }) {
            content.add(modelAnchor)
            print("Added missing modelAnchor to scene")
        }
        
        if arViewModel.sharedAnchorEntity.parent == nil && !content.entities.contains(where: { $0.id == arViewModel.sharedAnchorEntity.id }) {
            content.add(arViewModel.sharedAnchorEntity)
            print("Added missing sharedAnchorEntity to scene")
        }
        
        // Check all models
        for model in placedModels {
            guard let entity = model.modelEntity else { continue }
            
            // Make sure entity is visible
            entity.isEnabled = true
            
            // If entity has never been positioned or has no parent, place it in front of the user
            if entity.transform.translation == .zero || entity.parent == nil {
                // If no parent, add to the model anchor
                if entity.parent == nil {
                    anchorToUse.addChild(entity)
                    print("Added \(entity.name) to scene")
                }
                
                // Position in front of user at eye level (world space)
                entity.setPosition([0, 0.1, -0.5], relativeTo: anchorToUse)
                model.position = entity.position
                
                // Apply model-specific scaling
                if model.modelType.rawValue.lowercased() == "pancakes" {
                    // Make pancakes smaller
                    entity.scale = SIMD3<Float>(repeating: 0.08)
                } else if model.modelType.rawValue.lowercased() == "heart" || 
                          model.modelType.rawValue.lowercased() == "arterieshead" {
                    // Make other models larger
                    entity.scale = SIMD3<Float>(repeating: 0.2)
                } else {
                    // Default scale for any other models
                    entity.scale = SIMD3<Float>(repeating: 0.15)
                }
                model.scale = entity.scale
                
                print("Positioned \(entity.name) at \(entity.position) with scale \(entity.scale)")
            }
            
            // Visual highlight for selected model
            if model.modelType == selectedModelID {
                // If this model is selected, make it visually distinct
                if entity.components[SelectionComponent.self] == nil {
                    entity.components.set(SelectionComponent())
                    
                    // Create a visual highlight around the selected model
                    // No need to cast, just use the entity directly
                    
                    // Check if we already have a highlight entity
                    if entity.findEntity(named: "selectionHighlight") == nil {
                        // Create a simple highlight
                        let bounds = entity.visualBounds(relativeTo: nil)
                        let highlightSize = SIMD3<Float>(
                            bounds.extents.x * 1.05,
                            bounds.extents.y * 1.05,
                            bounds.extents.z * 1.05
                        )
                        
                        // Create a simple blue wireframe box
                        let boxMaterial = SimpleMaterial(
                            color: .blue,
                            roughness: 0.5,
                            isMetallic: false
                        )
                        
                        let boxMesh = MeshResource.generateBox(
                            size: highlightSize,
                            cornerRadius: 0.01
                        )
                        
                        let highlightEntity = ModelEntity(
                            mesh: boxMesh,
                            materials: [boxMaterial]
                        )
                        
                        // Name it for later reference
                        highlightEntity.name = "selectionHighlight"
                        
                        // Position at the same center as the model
                        highlightEntity.position = SIMD3<Float>(0, 0, 0)
                        
                        // Set transparency for the material
                        let transparentMaterial = SimpleMaterial(
                            color: UIColor.blue.withAlphaComponent(0.2),
                            roughness: 0.5,
                            isMetallic: false
                        )
                        
                        // Apply the transparent material
                        highlightEntity.model?.materials = [transparentMaterial]
                        
                        // Make sure our main model stays visible
                        entity.isEnabled = true
                        
                        // Add it as a child
                        entity.addChild(highlightEntity)
                    }
                    
                    print("Added selection highlight to \(model.modelType.rawValue)")
                }
            } else {
                // If this model was previously selected but isn't anymore, remove the highlight
                if entity.components[SelectionComponent.self] != nil {
                    entity.components.remove(SelectionComponent.self)
                    
                    // Remove the highlight entity
                    if let highlightEntity = entity.findEntity(named: "selectionHighlight") {
                        highlightEntity.removeFromParent()
                        print("Removed selection highlight from \(model.modelType.rawValue)")
                    }
                }
            }
            
            // Check for transform changes; broadcast if changed
            let currentMatrix = entity.transform.matrix
            if let lastMatrix = transformCache.lastTransforms[entity.id],
               lastMatrix != currentMatrix {
                connectivity.broadcastTransformIfNeeded(entity: entity, arViewModel: arViewModel)
                self.transformCache.lastTransforms[entity.id] = currentMatrix
            } else if transformCache.lastTransforms[entity.id] == nil {
                self.transformCache.lastTransforms[entity.id] = currentMatrix
            }
        }
    }

    // MARK: - Gestures
    
    // Tap gesture for model selection
    var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                Task { @MainActor in
                    let entity = value.entity
                    let name = entity.name.isEmpty ? "unnamed entity" : entity.name
                    
                    // Only handle actual models, not reference spheres
                    if let model = self.modelDict[entity] {
                        // Set this model as selected
                        self.selectedModelID = model.modelType
                        
                        // Make sure it stays visible
                        entity.isEnabled = true
                        
                        // If it's a child of a highlight or some other auxiliary object, make sure the parent is visible too
                        if let parent = entity.parent {
                            parent.isEnabled = true
                        }
                        
                        print("🎯 SELECT: Tapped \(name) - now selected")
                    }
                }
            }
    }
    
    // Drag gesture with extremely reduced sensitivity
    var dragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                Task { @MainActor in
                    // Try to get the model, but also support reference spheres
                    let entity = value.entity
                    let name = entity.name.isEmpty ? "unnamed entity" : entity.name
                    // Check if this is a model (used for logging)
                    
                    // Get translation in world space with MUCH lower sensitivity
                    let translation = value.translation3D
                    
                    // Convert to SIMD with heavily dampened values (100x less sensitive)
                    let delta = SIMD3<Float>(
                        Float(translation.x) * 0.0001, // Very small multiplier for precision
                        Float(translation.y) * 0.0001,
                        Float(translation.z) * 0.0001
                    )
                    
                    // Apply smoothing and clamping to limit movement per frame
                    let smoothedDelta = SIMD3<Float>(
                        min(max(delta.x, -0.01), 0.01),  // Clamp to max 0.01 units per frame
                        min(max(delta.y, -0.01), 0.01),
                        min(max(delta.z, -0.01), 0.01)
                    )
                    
                    // Keep track of old position for logging
                    let oldPosition = entity.position
                    
                    // Apply directly to entity position
                    entity.position += smoothedDelta
                    
                    // Update model position if this is a model
                    if let model = self.modelDict[entity] {
                        model.position = entity.position
                        
                        // If this entity was interacted with, select it
                        self.selectedModelID = model.modelType
                        
                        // Send transform update during drag
                        if let arViewModel = model.arViewModel {
                            // Use the existing sendTransform which handles sync mode
                            arViewModel.sendTransform(for: entity)
                        }
                    }
                    
                    print("🔵 DRAG: \(name) from \(oldPosition) to \(entity.position)")
                }
            }
            .onEnded { value in
                Task { @MainActor in
                    let entity = value.entity
                    
                    // Update model data if this is a model
                    if let model = self.modelDict[entity] {
                        model.position = entity.position
                        
                        // Make sure this model remains selected
                        self.selectedModelID = model.modelType
                        
                        // Send transform to peers if needed
                        if let arViewModel = model.arViewModel {
                            arViewModel.sendTransform(for: entity)
                        }
                    }
                    
                    print("✅ Drag gesture ended for \(entity.name)")
                }
            }
    }
    
    // Scale gesture with dampened values for better control
    var scaleGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.001)
            .targetedToAnyEntity()
            .onChanged { value in
                Task { @MainActor in
                    let entity = value.entity
                    let name = entity.name.isEmpty ? "unnamed entity" : entity.name
                    
                    // Get the scale factor with MUCH stronger dampening
                    let rawScaleFactor = Float(value.gestureValue.magnification)
                    // Only apply 1% of scale changes for finer control
                    let scaleFactor = 1.0 + (rawScaleFactor - 1.0) * 0.01
                    
                    // The current scale to modify (from model if available)
                    let currentScale = self.modelDict[entity]?.scale ?? entity.scale
                    
                    // Calculate new scale with limits
                    let newScale = currentScale * scaleFactor
                    
                    // Ensure minimum scale for visibility and maximum for usability
                    let minScale: Float = 0.02
                    let maxScale: Float = 2.0
                    
                    entity.scale = SIMD3<Float>(
                        min(max(newScale.x, minScale), maxScale),
                        min(max(newScale.y, minScale), maxScale),
                        min(max(newScale.z, minScale), maxScale)
                    )
                    
                    // Update model scale immediately
                    if let model = self.modelDict[entity] {
                        model.scale = entity.scale
                        
                        // If this entity was interacted with, select it
                        self.selectedModelID = model.modelType
                    }
                    
                    // Logging
                    print("🔍 SCALE: \(name) to \(entity.scale)")
                    
                    // Send transform update during scale
                    if let model = self.modelDict[entity], let arViewModel = model.arViewModel {
                        arViewModel.sendTransform(for: entity)
                    }
                }
            }
            .onEnded { value in
                Task { @MainActor in
                    let entity = value.entity
                    
                    // Final update to model scale
                    if let model = self.modelDict[entity] {
                        model.scale = entity.scale
                        model.updateCollisionBox()
                        
                        // Make sure this model remains selected
                        self.selectedModelID = model.modelType
                        
                        // Send transform to peers if needed
                        if let arViewModel = model.arViewModel {
                            arViewModel.sendTransform(for: entity)
                        }
                    }
                    
                    print("✅ Scale gesture ended for \(entity.name) at \(entity.scale)")
                }
            }
    }
    
    // Rotation gesture with reduced sensitivity and proper model updates
    var rotationGesture: some Gesture {
        RotateGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                Task { @MainActor in
                    let entity = value.entity
                    let name = entity.name.isEmpty ? "unnamed entity" : entity.name
                    
                    // Get extremely dampened rotation (reduce sensitivity by 95%)
                    let originalAngle = Float(value.rotation.radians)
                    let dampedAngle = originalAngle * 0.05
                    
                    // Store initial rotation when gesture begins
                    if self.entityInitialRotations[entity] == nil {
                        self.entityInitialRotations[entity] = entity.transform.rotation
                        print("Initial rotation recorded for \(name)")
                    }
                    
                    if self.entityInitialRotations[entity] != nil {
                        // Choose rotation axis based on model type or default to Y-axis
                        let rotationAxis: SIMD3<Float>
                        
                        // For models, respect z-axis rotation property
                        if let model = self.modelDict[entity], model.modelType.shouldRotateAroundZAxis {
                            rotationAxis = [0, 0, 1] // Z-axis for heart models
                        } else {
                            rotationAxis = [0, 1, 0] // Y-axis for most objects
                        }
                        
                        // Create a direct rotation rather than incremental slerp for more predictable results
                        let newRotation = simd_quatf(angle: dampedAngle, axis: rotationAxis)
                        entity.transform.rotation = newRotation
                        
                        // Update model immediately for better feedback
                        if let model = self.modelDict[entity] {
                            model.rotation = entity.transform.rotation
                            
                            // If this entity was interacted with, select it
                            self.selectedModelID = model.modelType
                        }
                        
                        print("🔄 ROTATE: \(name) to angle \(dampedAngle)")
                        
                        // Send transform update during rotation
                        if let model = self.modelDict[entity], let arViewModel = model.arViewModel {
                            arViewModel.sendTransform(for: entity)
                        }
                    }
                }
            }
            .onEnded { value in
                Task { @MainActor in
                    let entity = value.entity
                    
                    // Update model rotation if this is a model
                    if let model = self.modelDict[entity] {
                        model.rotation = entity.transform.rotation
                        
                        // Make sure this model remains selected
                        self.selectedModelID = model.modelType
                        
                        // Send transform to peers if needed
                        if let arViewModel = model.arViewModel {
                            arViewModel.sendTransform(for: entity)
                        }
                    }
                    
                    // Clean up initial rotation reference
                    self.entityInitialRotations.removeValue(forKey: entity)
                    
                    print("✅ Rotation gesture ended for \(entity.name)")
                }
            }
    }
}
