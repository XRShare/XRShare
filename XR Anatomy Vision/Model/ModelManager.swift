//
//  ModelManager.swift
//  XR Anatomy
//
//  Created by XR Anatomy on 2025-03-11.
//


import SwiftUI
import RealityKit

/// Stores the last known transforms of Entities for comparison
final class TransformCache: ObservableObject {
    @Published var lastTransforms: [Entity.ID: simd_float4x4] = [:]
}

/// Manages placed models, gestures, and related logic
final class ModelManager: ObservableObject {
    @Published var placedModels: [Model] = []
    @Published var modelDict: [Entity: Model] = [:]
    @Published var entityInitialRotations: [Entity: simd_quatf] = [:]
    @Published var modelTypes: [ModelType] = []
    
    // Cache last transforms
    var transformCache = TransformCache()
    
    init() {
        loadModelTypes()
    }
    
    // MARK: - Model Type Loading
    
    func loadModelTypes() {
        self.modelTypes = ModelType.allCases()
        print("Loaded model types: \(modelTypes.map { $0.rawValue })")
    }
    
    // MARK: - Public Model Methods
    
    func loadModel(for modelType: ModelType, headAnchor: AnchorEntity, arViewModel: ARViewModel?) {
        Task {
            print("Attempting to load model: \(modelType.rawValue).usdz")
            let model = await Model.load(modelType: modelType)
            if let entity = model.modelEntity {
                modelDict[entity] = model
                placedModels.append(model)
                
                // Default position if not already set
                if await entity.position == SIMD3<Float>(repeating: 0.0) {
                    await entity.setPosition([0, 0, -1], relativeTo: headAnchor)
                    model.position = await entity.position
                }
                
                // Register with the synchronization service
                if let customService =
                    await arViewModel?.currentScene?.synchronizationService as? MyCustomConnectivityService {
                    customService.registerEntity(entity)
                }
                
                print("\(modelType.rawValue) chosen – model ready for placement")
                print("Placed \(modelType.rawValue) at position: \(await entity.transform.translation)")
            } else {
                print("Failed to load model entity for \(modelType.rawValue).usdz")
            }
        }
    }
    
    func reset() {
        placedModels.removeAll()
        modelDict.removeAll()
        entityInitialRotations.removeAll()
        transformCache.lastTransforms.removeAll()
    }
    
    // MARK: - AR/RealityKit Updates
    
    func updatePlacedModels(
        content: RealityViewContent,
        modelAnchor: AnchorEntity,
        connectivity: SessionConnectivity,
        arViewModel: ARViewModel
    ) {
        for model in placedModels {
            guard !model.isLoading(), let entity = model.modelEntity else {
                continue
            }
            // If not positioned yet, place in front of model anchor
            if entity.transform.translation == SIMD3<Float>(repeating: 0) {
                DispatchQueue.main.async {
                    entity.setPosition([0, 0, -1], relativeTo: modelAnchor)
                    model.position = entity.position
                }
            }
            // Ensure entity is a child of the modelAnchor
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
                // First time tracking this entity
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
                print("Rotation gesture ended for \(entity.name)")
            }
    }
}
