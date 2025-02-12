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
    var id: ModelType { modelType }

    init(modelType: ModelType) {
        self.modelType = modelType
        loadModelEntity()
    }

    static func == (lhs: Model, rhs: Model) -> Bool {
        lhs.modelType == rhs.modelType
    }

    private func loadModelEntity() {
        let filename = modelType.rawValue + ".usdz"
        Task {
            do {
                let entity = try await ModelEntity(named: filename)
                DispatchQueue.main.async {
                    self.modelEntity = entity
                    self.loadingState = .loaded
                }
            } catch {
                DispatchQueue.main.async {
                    self.loadingState = .failed(error)
                }
            }
        }
    }
}
