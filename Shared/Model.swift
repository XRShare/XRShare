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
    
    init(modelType: ModelType) {
        self.modelType = modelType
        Task {
            await loadModelEntity()
        }
    }
    
    private func loadModelEntity() async {
        let filename = "\(modelType.rawValue).usdz"
        do {
            // Specify Bundle.main explicitly (or another bundle if your resources are in a module)
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
        // Implement collision box update if needed, or leave as a stub.
        print("updateCollisionBox called")
    }
}
