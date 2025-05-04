//
//  ModelTransformPayload.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-14.
//


import Foundation

struct ModelTransformPayload: Codable {
    /// The unique instance identifier of the model being transformed.
    let instanceID: String // Use instanceID consistently
    /// The transform (position, rotation, scale) as a 16-element array representing a 4x4 matrix.
    let transform: [Float]
    /// Optional: The type of model (e.g., "Heart"). Can be useful for debugging but not primary identification.
    let modelType: String?
    /// Indicates if the transform is relative to the shared anchor (image or object).
    let isRelativeToSharedAnchor: Bool // Renamed for clarity and made non-optional
}

struct AnchorTransformPayload: Codable {
    let anchorData: Data
    /// Identifier for the anchor itself, potentially derived from its ID.
    let anchorID: String // Changed from modelID for clarity
    /// The transform of the anchor.
    let transform: [Float]
    /// Optional: The type of model associated with this anchor, if any.
    let modelType: String?
}