//
//  ModelType.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-14.
//


import Foundation
import RealityKit

enum ModelCategory: String, CaseIterable, Identifiable {
    var id: String {self.rawValue}
        
    case anatomy
    case food
    case car
    case airplane
    case bird
}

struct ModelType: Hashable, Identifiable {
    let rawValue: String
    
    // Instead of a random UUID, use the rawValue as the basis for the ID
    // This ensures models with the same rawValue have the same ID
    var id: String { rawValue.lowercased() }
    
    static let categoryMap: [String: ModelCategory] = [
        "heart": .anatomy,
        "arterieshead": .anatomy,
        "pancakes": .food
        ]
    
    var category: ModelCategory? {
        ModelType.categoryMap[rawValue.lowercased()]
    }
    
    /// Models that should rotate around the Z‑axis (if needed)
    static let zAxisRotationModels: [String] = ["arterieshead", "brain", "heart", "heart2k"]
    
    func createModelEntity() -> ModelEntity? {
        let filename = rawValue + ".usdz"
        do {
            // First try in the models subdirectory
            if let modelURL = Bundle.main.url(forResource: rawValue, withExtension: "usdz", subdirectory: "models") {
                let me = try ModelEntity.loadModel(contentsOf: modelURL)
                return me
            } else {
                // Fallback to the main bundle
                let me = try ModelEntity.loadModel(named: filename)
                return me
            }
        } catch {
            print("Error loading \(filename): \(error.localizedDescription)")
            return nil
        }
    }
    
    static func allCases() -> [ModelType] {
        // First, try to find models in the "models" subdirectory
        var modelTypes: [ModelType] = []
        
        if let modelDirURL = Bundle.main.resourceURL?.appendingPathComponent("models"),
           let fileURLs = try? FileManager.default.contentsOfDirectory(at: modelDirURL, includingPropertiesForKeys: nil) {
            for url in fileURLs where url.pathExtension == "usdz" {
                let name = url.deletingPathExtension().lastPathComponent
                modelTypes.append(ModelType(rawValue: name))
            }
        }
        
        // If no models found in subdirectory, fall back to main bundle
        if modelTypes.isEmpty {
            if let urls = Bundle.main.urls(forResourcesWithExtension: "usdz", subdirectory: nil) {
                for url in urls {
                    let name = url.deletingPathExtension().lastPathComponent
                    modelTypes.append(ModelType(rawValue: name))
                }
            } else {
                print("No .usdz files found in either models directory or main bundle.")
            }
        }
        
        if modelTypes.isEmpty {
            print("WARNING: No 3D models found. Please add .usdz files to the 'models' folder.")
        }
        
        return modelTypes
    }
    
    var shouldRotateAroundZAxis: Bool {
        Self.zAxisRotationModels.contains(rawValue.lowercased())
    }
    
    static func ==(lhs: ModelType, rhs: ModelType) -> Bool {
        lhs.rawValue.lowercased() == rhs.rawValue.lowercased()
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue.lowercased())
    }
}