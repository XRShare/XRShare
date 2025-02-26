import RealityKit
import SwiftUI
import Foundation

final class Model: ObservableObject, Identifiable {
    enum LoadingState {
        case loading, loaded, failed(Error)
    }
    
    let modelType: ModelType
    @Published var modelEntity: ModelEntity?
    @Published var loadingState: LoadingState = .loading
    
    // Properties for scene placement
    var position: SIMD3<Float> = SIMD3<Float>(repeating: 0)
    var scale: SIMD3<Float> = SIMD3<Float>(repeating: 1)
    
    var id: ModelType { modelType }
    
    // Synchronous initializer; note it does NOT load immediately.
    init(modelType: ModelType) {
        self.modelType = modelType
    }
    
    /// An asynchronous factory method that creates a Model and waits until its entity is loaded.
    static func load(modelType: ModelType) async -> Model {
        let model = Model(modelType: modelType)
        await model.loadModelEntity()
        return model
    }
    
    /// Loads the modelEntity asynchronously.
    fileprivate func loadModelEntity() async {
        let filename = "\(modelType.rawValue).usdz"
        do {
            // Use Bundle.main explicitly (or another bundle if needed)
            self.modelEntity = try await ModelEntity(named: filename, in: Bundle.main)
            self.loadingState = .loaded
            print("Successfully loaded \(filename)")
        } catch {
            print("Error loading model \(filename): \(error)")
            self.loadingState = .failed(error)
        }
    }
    
    func isLoading() -> Bool {
        if case .loading = loadingState { return true }
        return false
    }
    
    func updateCollisionBox() {
        print("updateCollisionBox called")
    }
}
