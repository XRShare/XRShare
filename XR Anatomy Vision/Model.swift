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
    private var cancellable: AnyCancellable?

    var id: ModelType { modelType } // Conform to Identifiable using modelType as the id

    init(modelType: ModelType) {
        self.modelType = modelType
        loadModelEntity()
    }

    // Conform to Equatable
    static func == (lhs: Model, rhs: Model) -> Bool {
        return lhs.modelType == rhs.modelType
    }

    private func loadModelEntity() {
        let filename = modelType.rawValue + ".usdz"
        print("Attempting to load model:", filename)

        Task {
            do {
                // Use the updated asynchronous initializer
                let modelEntity = try await ModelEntity(named: filename)
                self.modelEntity = modelEntity
                print("Model \(filename) loaded successfully.")
                self.loadingState = .loaded
            } catch {
                print("Error loading model \(filename): \(error.localizedDescription)")
                self.loadingState = .failed(error)
            }
        }
    }
}
