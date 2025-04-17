import Foundation

/// Payload for broadcasting the addition of a model.
struct AddModelPayload: Codable {
    /// A unique identifier for this specific instance of the model being added.
    let instanceID: String // Keep this as the primary identifier
    /// The type of model to add (e.g., "Heart", "pancakes"). Used for loading the correct model resource.
    let modelType: String
    /// The initial transform (position, rotation, scale) as a 16-element array.
    let transform: [Float]
    /// Indicates if the transform is relative to the shared anchor (image or object).
    let isRelativeToSharedAnchor: Bool // Renamed for clarity
}

/// Payload for broadcasting the removal of a model.
struct RemoveModelPayload: Codable {
    /// The unique instance identifier of the model to remove.
    let instanceID: String // Use instanceID consistently
}

/// Payload for a simple test message.
struct TestMessagePayload: Codable {
    let message: String
    let senderName: String
}