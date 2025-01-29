//ModelType
import RealityKit
import Foundation

struct ModelType: Hashable, Identifiable {
    let rawValue: String
    let id = UUID() // Unique identifier for each model type

    // Array of model names that should rotate around the z-axis
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
