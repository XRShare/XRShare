//
//  TransformCache.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-03-11.
//


import RealityKit
import SwiftUI

/// Stores the last known transforms of Entities for comparison
final class TransformCache: ObservableObject {
    @Published var lastTransforms: [Entity.ID: simd_float4x4] = [:]
}