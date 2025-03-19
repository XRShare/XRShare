import SwiftUI
import RealityKit

/// Manages placed models, gestures, and related logic
final class ModelManager: ObservableObject {
    @Published var placedModels: [Model] = []
    @Published var modelDict: [Entity: Model] = [:]
    @Published var entityInitialRotations: [Entity: simd_quatf] = [:]
    @Published var modelTypes: [ModelType] = []

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
                }
                let customService = await MainActor.run { arViewModel?.currentScene?.synchronizationService }
                if let customService = customService as? MyCustomConnectivityService {
                    customService.registerEntity(entity, modelType: modelType)
                }
                print("\(modelType.rawValue) chosen – model loaded (not placed yet)")
            } else {
                print("Failed to load model entity for \(modelType.rawValue).usdz")
            }
        }
    }

    // MARK: - Remove a Single Model
    @MainActor func removeModel(_ model: Model) {
        guard let entity = model.modelEntity else { return }
        entity.removeFromParent()
        placedModels.removeAll { $0.id == model.id }
        modelDict = modelDict.filter { $0.value.id != model.id }
    }
    
    @MainActor func reset() {
        // Remove all from the scene
        placedModels.forEach { model in
            model.modelEntity?.removeFromParent()
        }
        placedModels.removeAll()
        modelDict.removeAll()
        entityInitialRotations.removeAll()
        transformCache.lastTransforms.removeAll()
    }
    
    // MARK: - Update the 3D Scene
    @MainActor func updatePlacedModels(
        content: RealityViewContent,
        modelAnchor: AnchorEntity,
        connectivity: SessionConnectivity,
        arViewModel: ARViewModel
    ) {
        for model in placedModels {
            guard let entity = model.modelEntity else { continue }
            
            // If entity has never been positioned, place it in front of modelAnchor
            if entity.transform.translation == .zero {
                entity.setPosition([0, 0, -1], relativeTo: modelAnchor)
                model.position = entity.position
            }
            
            // Ensure the entity is a child of modelAnchor
            if entity.parent == nil {
                modelAnchor.addChild(entity)
                content.add(entity)
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
                    }
                    
                    // Logging
                    print("🔍 SCALE: \(name) to \(entity.scale)")
                }
            }
            .onEnded { value in
                Task { @MainActor in
                    let entity = value.entity
                    
                    // Final update to model scale
                    if let model = self.modelDict[entity] {
                        model.scale = entity.scale
                        model.updateCollisionBox()
                        
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
                    
                    if let initialRotation = self.entityInitialRotations[entity] {
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
                        }
                        
                        print("🔄 ROTATE: \(name) to angle \(dampedAngle)")
                    }
                }
            }
            .onEnded { value in
                Task { @MainActor in
                    let entity = value.entity
                    
                    // Update model rotation if this is a model
                    if let model = self.modelDict[entity] {
                        model.rotation = entity.transform.rotation
                        
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
