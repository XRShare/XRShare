//
//  ModelTransformPayload.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-14.
//


import Foundation

struct ModelTransformPayload: Codable {
    let modelID: String
    let transform: [Float] // a 16-element array representing a 4x4 matrix
    let modelType: String?
    let isRelativeToImageAnchor: Bool?
}

struct AnchorTransformPayload: Codable {
    let anchorData: Data
    let modelID: String
    let transform: [Float]
    let modelType: String?
}