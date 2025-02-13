import RealityKit
import Combine
import Foundation

class Model: ObservableObject, Identifiable, Equatable {
    enum LoadingState {
        case loading
        case loaded
        case failed(Error)
    }

    let modelType: ModelType
    @Published var modelEntity: ModelEntity?
    @Published var loadingState: LoadingState = .loading
    @Published var initialPosision: SIMD3<Float>? = nil
    @Published var initialSale: SIMD3<Float>? = nil
    private var cancellable: AnyCancellable?

    var id: ModelType { modelType } // Conform to Identifiable using modelType as the id
    var scale =  SIMD3<Float>(repeating: 1.0)
    var position = SIMD3<Float>(repeating:0.0)
    var center = SIMD3<Float>(repeating: 0.0)
    var rotation = simd_quatf()

    init(modelName: String) async {
        self.modelType = ModelType(rawValue: modelName)
        await loadModelEntity()
        //while isLoading() {}
    }

    // Conform to Equatable
    static func == (lhs: Model, rhs: Model) -> Bool {
        return lhs.modelType == rhs.modelType
    }
    
    public func isLoading() -> Bool {
        if case  LoadingState.loading = self.loadingState {
            return true
        }
        return false
    }
    public func updateCollisionBox() {
        let model = modelEntity!
        Task{
            let bounds = await model.visualBounds(relativeTo: nil)
            let collisionBox = await ShapeResource.generateBox(
                width: bounds.extents.x,
                height: bounds.extents.y,
                depth: bounds.extents.z
            )
            
            await model.components.set(CollisionComponent(shapes: [collisionBox], mode: .trigger))
        }
    }

    private func loadModelEntity() async {
        let filename = modelType.rawValue + ".usdz"
        print("Attempting to load model:", filename)

        do {
            // Use the updated asynchronous initializer
            let modelEntity = try await ModelEntity(named: filename)
            
            
            self.modelEntity = modelEntity
            print("Model \(filename) loaded successfully.")
            self.loadingState = .loaded
            
            // Configure collision and input components for gestures
           let bounds = await modelEntity.visualBounds(relativeTo: nil)
           let collisionBox = await ShapeResource.generateBox(
               width: bounds.extents.x,
               height: bounds.extents.y,
               depth: bounds.extents.z
           )
            await modelEntity.components.set(CollisionComponent(shapes: [collisionBox], mode:.trigger))
            await modelEntity.components.set(InputTargetComponent(allowedInputTypes: .indirect))
            center = bounds.center
            

            
        } catch {
            print("Error loading model \(filename): \(error.localizedDescription)")
            self.loadingState = .failed(error)
        }
    }

}
