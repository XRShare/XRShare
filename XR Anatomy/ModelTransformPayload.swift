//
//  ModelTransformPayload.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-12.
//


import Foundation

struct ModelTransformPayload: Codable {
    let modelID: String
    let transform: [Float] // 16-element 4x4 matrix
}

struct AnchorTransformPayload: Codable {
    let anchorData: Data
    let modelID: String
    let transform: [Float]
}