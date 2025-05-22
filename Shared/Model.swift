import RealityKit
import SwiftUI
import Foundation
import Combine
import ARKit

/// Represents a 3D anatomical model with loading and placement capabilities
@MainActor
final class Model: ObservableObject, @preconcurrency Identifiable {
    enum LoadingState: Equatable {
        case notStarted, loading, loaded, failed(Error)
        
        static func == (lhs: LoadingState, rhs: LoadingState) -> Bool {
            switch (lhs, rhs) {
            case (.notStarted, .notStarted), (.loading, .loading), (.loaded, .loaded):
                return true
            case (.failed(_), .failed(_)):
                return true
            default:
                return false
            }
        }
    }
    
    let modelType: ModelType
    @Published var modelEntity: ModelEntity?
    @Published var loadingState: LoadingState = .notStarted
    
    // Properties for scene placement
    var position: SIMD3<Float> = SIMD3<Float>(repeating: 0)
    var scale: SIMD3<Float> = SIMD3<Float>(repeating: 1)
    var rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    
    // Reference to ARViewModel for synchronization
    weak var arViewModel: ARViewModel?
    
    var cancellables = Set<AnyCancellable>()
    
    // Use ModelType for general identification, but need a unique ID per instance
    var id: ModelType { modelType }
    let instanceUUID = UUID() // Unique identifier for each instance
    var entity: Entity?
    
    // MARK: - Initialization
    
    /// Creates a Model but does not start loading immediately.
    init(modelType: ModelType, arViewModel: ARViewModel? = nil) {
        self.modelType = modelType
        self.arViewModel = arViewModel
    }
    
    /// An asynchronous factory method that creates a Model and loads its entity.
    static func load(modelType: ModelType, arViewModel: ARViewModel? = nil) async -> Model {
        let model = Model(modelType: modelType, arViewModel: arViewModel)
        await model.loadModelEntity()
        return model
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
    
    // MARK: - Loading
    
    /// Loads the modelEntity asynchronously on the main actor.
    @MainActor
    func loadModelEntity() async {
        // Skip if we're already loaded or loading
        guard case .notStarted = loadingState else { return }
        
        await MainActor.run {
            loadingState = .loading
        }
        
        let filename = "\(modelType.rawValue).usdz"
        do {
            
            // First try to load from models directory
            if let modelURL = Bundle.main.url(forResource: modelType.rawValue, withExtension: "usdz", subdirectory: "models") {
                self.modelEntity = try await ModelEntity(contentsOf: modelURL)
              
                
            } else {
                // Fallback to main bundle
                self.modelEntity = try await ModelEntity(named: filename, in: Bundle.main)
               
            }
            
            
            applyInteractivityRecursively()
            
            // Apply the correct rotation based on model type
            if let entity = self.modelEntity {
                entity.generateCollisionShapes(recursive: true)
                
                // Add input target component for gesture interaction
                entity.components.set(InputTargetComponent())
                
                // Add hover effect to show interactivity
                entity.components.set(HoverEffectComponent())
                
                // Name the entity meaningfully for better identification
                entity.name = "Model_\(modelType.rawValue)"
                
                // Apply Z-axis rotation correction if needed
                if modelType.shouldRotateAroundZAxis {
                    // Rotate to correct initial orientation
                    entity.orientation = simd_quatf(angle: .pi/2, axis: SIMD3<Float>(1, 0, 0))
                }
                
                // REMOVED: Fallback material application. Let the USDZ define its own materials.
                // if entity.model?.materials.isEmpty == true {
                //     entity.model?.materials = [SimpleMaterial(color: .white, isMetallic: false)]
                // }
                
                // Set initial scale based on model type
                if modelType.rawValue.lowercased() == "pancakes" {
                    entity.scale = [0.04, 0.04, 0.04] // Further reduced scale for pancakes
                } else if modelType.rawValue.lowercased() == "heart" ||
                          modelType.rawValue.lowercased() == "arterieshead" {
                    entity.scale = [0.2, 0.2, 0.2] // Larger scale for anatomy models
                } else {
                    entity.scale = [0.15, 0.15, 0.15] // Default scale
                }
                
                // Add components for synchronization
                entity.components[ModelTypeComponent.self] = ModelTypeComponent(type: modelType)
                entity.components[LastTransformComponent.self] = LastTransformComponent(matrix: entity.transform.matrix)
                
                // Add collision component for interaction
                if entity.collision == nil {
                    entity.collision = CollisionComponent(shapes: [.generateBox(size: entity.visualBounds(relativeTo: nil).extents)])
                }
                
                // Add InstanceID component
                if entity.components[InstanceIDComponent.self] == nil {
                    entity.components.set(InstanceIDComponent())
                }
            }
            
            await MainActor.run {
                self.loadingState = .loaded
            }
            print("Successfully loaded \(filename)")
        } catch {
            print("Error loading model \(filename): \(error)")
            await MainActor.run {
                self.loadingState = .failed(error)
            }
        }
    }
    
    func applyInteractivityRecursively() {
        guard let entity = modelEntity else { return }
        Self.applyComponents(to: entity)
    }

    private static func applyComponents(to entity: Entity) {
        entity.components.set(InputTargetComponent(allowedInputTypes: .all))
        entity.components.set(HoverEffectComponent())

        if let modelEntity = entity as? ModelEntity {
            modelEntity.generateCollisionShapes(recursive: false)
        }

        for child in entity.children {
            applyComponents(to: child)
        }
    }
    
    func printHierarchy(of entity: Entity, indent: String = "") {
            print("\(indent)- \(entity.name)")
            for child in entity.children {
                printHierarchy(of: child, indent: indent + "  ")
            }
        }
    
    // MARK: - Transform Updates
    
    /// Update the transform and notify peers of the change
    @MainActor
    func updateTransformAndNotify() {
        guard let entity = modelEntity else { return }
        
        // Store last known transform matrix
        let currentMatrix = entity.transform.matrix
        
        // Get the last stored matrix
        if let lastMatrix = entity.components[LastTransformComponent.self]?.matrix,
           !simd_almost_equal_elements(currentMatrix, lastMatrix, 0.0001) {
            
            // Update the cached transform
            entity.components[LastTransformComponent.self] = LastTransformComponent(matrix: currentMatrix)
            
            // Broadcast the transform change
            #if os(iOS)
            if let arViewModel = self.arViewModel {
                // We'll implement broadcastTransform in ARViewModel
                arViewModel.broadcastModelTransform(entity: entity, modelType: modelType)
            }
            #endif
        }
    }
    
    // MARK: - Status helpers
    
    /// Returns true if the model is currently in the loading state
    func isLoading() -> Bool {
        if case .loading = loadingState { return true }
        return false
    }
    
    /// Returns true if the model has successfully loaded
    func isLoaded() -> Bool {
        if case .loaded = loadingState { return true }
        return false
    }
    
    /// Returns true if the model failed to load
    func didFail() -> Bool {
        if case .failed(_) = loadingState { return true }
        return false
    }
    
    /// Returns the error message if loading failed, or nil otherwise
    func errorMessage() -> String? {
        if case .failed(let error) = loadingState {
            return error.localizedDescription
        }
        return nil
    }
    
    /// Updates collision shapes for the model entity
    @MainActor
    func updateCollisionBox() {
        guard let entity = modelEntity else { return }
        Task {
            entity.generateCollisionShapes(recursive: true)
            print("Updated collision shapes for \(modelType.rawValue)")
        }
    }
}

// MARK: - Components for Synchronization
struct ModelTypeComponent: Component {
    let type: ModelType
}

struct LastTransformComponent: Component {
    var matrix: simd_float4x4
}

// Component to mark a model as currently selected
struct SelectionComponent: Component {}
