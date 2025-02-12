//
//  ModelType.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-12.
//


import RealityKit
import Foundation

struct ModelType: Hashable, Identifiable {
    let rawValue: String
    let id = UUID()

    static let zAxisRotationModels: [String] = ["arteriesHead","brain","heart","heart2K"]

    func createModelEntity() -> ModelEntity? {
        let filename = rawValue + ".usdz"
        do {
            let me = try ModelEntity.loadModel(named: filename)
            return me
        } catch {
            print("Error loading \(filename): \(error)")
            return nil
        }
    }

    static func allCases() -> [ModelType] {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "usdz", subdirectory: nil) else {
            print("No .usdz found")
            return []
        }
        return urls.map {
            let name = $0.deletingPathExtension().lastPathComponent
            return ModelType(rawValue: name)
        }
    }

    var shouldRotateAroundZAxis: Bool {
        Self.zAxisRotationModels.contains(rawValue)
    }

    static func ==(lhs: ModelType, rhs: ModelType) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}