// Model class and ModelType struct

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

    var id: ModelType { modelType } // Conform to Identifiable using modelType as the id

    init(modelType: ModelType) {
        self.modelType = modelType
        loadModelEntity()
    }

    private func loadModelEntity() {
        // Update the filename path to include the "models" folder
        let filename = modelType.rawValue + ".usdz"
        cancellable = ModelEntity.loadModelAsync(named: filename)
            .sink(receiveCompletion: { [weak self] loadCompletion in
                switch loadCompletion {
                case .failure(let error):
                    print("Error loading model \(filename): \(error)")
                    self?.loadingState = .failed(error)
                case .finished:
                    break
                }
            }, receiveValue: { [weak self] modelEntity in
                self?.modelEntity = modelEntity
                print("Model \(filename) loaded successfully.")
                self?.loadingState = .loaded
            })
    }
}



struct ModelType: Hashable, Identifiable {
    let rawValue: String
    let id = UUID() // Unique identifier for each model type

    // List of model (file names) that should rotate around the z-axis instead of y (all models from Shane seem to need this)
    static let zAxisRotationModels: [String] = ["arteriesHead", "brain", "heart", "heart2K"]

    // Method to load the model entity from the filename
    func createModelEntity() -> ModelEntity? {
        let filename = rawValue + ".usdz"
        do {
            let modelEntity = try ModelEntity.loadModel(named: filename)
            return modelEntity
        } catch {
            print("Error loading model \(filename): \(error)")
            return nil
        }
    }

    // Method to retrieve all ModelType instances based on available .usdz files
    static func allCases() -> [ModelType] {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "usdz", subdirectory: nil) else {
            print("No .usdz files found in the bundle")
            return []
        }

        return urls.map { url in
            let modelName = url.deletingPathExtension().lastPathComponent
            return ModelType(rawValue: modelName)
        }
    }

    // Check if this model should rotate around the z-axis
    var shouldRotateAroundZAxis: Bool {
        return ModelType.zAxisRotationModels.contains(rawValue)
    }

    // Conforms to Equatable based on rawValue
    static func ==(lhs: ModelType, rhs: ModelType) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }

    // Manual Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}
