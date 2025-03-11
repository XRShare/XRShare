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
            if let entity = model.modelEntity {
                // Add to placedModels
                await MainActor.run {
                    self.modelDict[entity] = model
                    self.placedModels.append(model)
                }
                // Optionally register with custom sync
                if let customService = await arViewModel?.currentScene?.synchronizationService
                    as? MyCustomConnectivityService {
                    customService.registerEntity(entity, modelType: modelType)
                }
                print("\(modelType.rawValue) chosen – model loaded (not placed yet)")
            } else {
                print("Failed to load model entity for \(modelType.rawValue).usdz")
            }
        }
    }

    // MARK: - Remove a Single Model
    func removeModel(_ model: Model) {
        guard let entity = model.modelEntity else { return }
        entity.removeFromParent()
        placedModels.removeAll { $0.id == model.id }
        modelDict = modelDict.filter { $0.value.id != model.id }
    }
    
    func reset() {
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
    func updatePlacedModels(
        content: RealityViewContent,
        modelAnchor: AnchorEntity,
        connectivity: SessionConnectivity,
        arViewModel: ARViewModel
    ) {
        for model in placedModels {
            guard let entity = model.modelEntity else { continue }
            
            // If entity has never been positioned, place it in front of modelAnchor
            if entity.transform.translation == .zero {
                DispatchQueue.main.async {
                    entity.setPosition([0, 0, -1], relativeTo: modelAnchor)
                    model.position = entity.position
                }
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
                DispatchQueue.main.async {
                    self.transformCache.lastTransforms[entity.id] = currentMatrix
                }
            } else if transformCache.lastTransforms[entity.id] == nil {
                // first time tracking
                DispatchQueue.main.async {
                    self.transformCache.lastTransforms[entity.id] = currentMatrix
                }
            }
        }
    }

    // MARK: - Gestures
    
    var dragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                guard let model = self.modelDict[value.entity],
                      let parent = value.entity.parent else { return }
                let translation = value.translation3D
                let convertedTranslation = value.convert(translation, from: .local, to: parent)
                let newPosition = model.position + convertedTranslation
                value.entity.position = newPosition
            }
            .onEnded { value in
                guard let model = self.modelDict[value.entity] else { return }
                model.position = value.entity.position
                // Broadcast transform change
                if let arViewModel = model.arViewModel {
                    arViewModel.sendTransform(for: value.entity)
                }
                print("Drag gesture ended for \(value.entity.name)")
            }
    }
    
    var scaleGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.001)
            .targetedToAnyEntity()
            .onChanged { value in
                let entity = value.entity
                guard let model = self.modelDict[entity] else { return }
                let magnification = Float(value.gestureValue.magnification)
                let newScale = model.scale * magnification
                entity.scale = newScale
                print("Entity scaled to \(entity.scale)")
            }
            .onEnded { value in
                guard let model = self.modelDict[value.entity] else { return }
                model.scale = value.entity.scale
                model.updateCollisionBox()
                // Broadcast transform change
                if let arViewModel = model.arViewModel {
                    arViewModel.sendTransform(for: value.entity)
                }
                print("Scaling gesture ended")
            }
    }
    
    var rotationGesture: some Gesture {
        RotateGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                let entity = value.entity
                if self.entityInitialRotations[entity] == nil {
                    self.entityInitialRotations[entity] = entity.transform.rotation
                    print("Initial rotation recorded for \(entity.name)")
                }
                if let initialRotation = self.entityInitialRotations[entity] {
                    let angle = Float(value.rotation.radians)
                    let targetRotation = initialRotation * simd_quatf(angle: angle, axis: [0, 0, 1])
                    let currentRotation = entity.transform.rotation
                    let newRotation = simd_slerp(currentRotation, targetRotation, 0.2)
                    entity.transform.rotation = newRotation
                    print("Entity rotated by \(value.rotation.radians) radians")
                }
            }
            .onEnded { value in
                let entity = value.entity
                self.entityInitialRotations.removeValue(forKey: entity)
                // Broadcast transform change
                if let model = self.modelDict[entity],
                   let arViewModel = model.arViewModel {
                    arViewModel.sendTransform(for: entity)
                }
                print("Rotation gesture ended for \(entity.name)")
            }
    }
}
