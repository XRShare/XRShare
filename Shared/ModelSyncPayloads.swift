import Foundation

/// Payload for broadcasting the addition of a model.
struct AddModelPayload: Codable {
    /// A unique identifier for this specific instance of the model being added.
    let instanceID: String
    /// The type of model to add (e.g., "Heart", "pancakes").
    let modelType: String
    /// The initial transform (position, rotation, scale) as a 16-element array.
    let transform: [Float]
    /// Indicates if the transform is relative to the image anchor.
    let isRelativeToImageAnchor: Bool
}

/// Payload for broadcasting the removal of a model.
struct RemoveModelPayload: Codable {
    /// The unique instance identifier of the model to remove.
    let instanceID: String
}

/// Payload for a simple test message.
struct TestMessagePayload: Codable {
    let message: String
    let senderName: String
}