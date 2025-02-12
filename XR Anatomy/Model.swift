import RealityKit
import Foundation
import Combine

class Model: ObservableObject, Identifiable {
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

    private func loadModelEntity() {
        let filename = modelType.rawValue + ".usdz"
        cancellable = ModelEntity.loadModelAsync(named: filename)
            .sink(receiveCompletion: { [weak self] completion in
                switch completion {
                case .failure(let err):
                    self?.loadingState = .failed(err)
                case .finished:
                    break
                }
            }, receiveValue: { [weak self] entity in
                self?.modelEntity = entity
                self?.loadingState = .loaded
            })
    }
}
