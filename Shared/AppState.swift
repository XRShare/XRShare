import SwiftUI
import ARKit

/// Application-wide AR tracking state used mainly by the visionOS build.
@MainActor
class AppState: ObservableObject {

    // Providers
    @Published var imageTrackingProvider: ImageTrackingProvider? = nil
    @Published var objectTrackingProvider: ObjectTrackingProvider? = nil

    // Alert forwarding
    @Published var alertItem: AlertItem? = nil

    // Auto-start flags
    @Published var autoStartImageTracking: Bool = true

    // MARK: Tracking helpers
    func startImageTracking(provider: ImageTrackingProvider) {
        imageTrackingProvider = provider
        objectTrackingProvider = nil
    }

    func startObjectTracking(provider: ObjectTrackingProvider) {
        objectTrackingProvider = provider
        imageTrackingProvider = nil
    }

    func stopTracking() {
        imageTrackingProvider = nil
        objectTrackingProvider = nil
    }
}
