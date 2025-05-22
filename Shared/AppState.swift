import SwiftUI

// Import ARKit only when it exists (visionOS, iOS 17+)
#if canImport(ARKit)
import ARKit
#endif

/// Application-wide AR / tracking state.
/// Only visionOS currently uses the tracking providers; on other platforms the
/// symbols are stubbed so the file compiles under a shared target.
@MainActor
class AppState: ObservableObject {

#if os(visionOS)
    // MARK: Tracking providers (visionOS only)
    @Published var imageTrackingProvider: ImageTrackingProvider? = nil
#endif

    // MARK: Shared UI state
    @Published var alertItem: AlertItem? = nil
    @Published var autoStartImageTracking: Bool = true

#if os(visionOS)
    // MARK: Tracking helper methods
    func startImageTracking(provider: ImageTrackingProvider) {
        imageTrackingProvider = provider
    }


    func stopTracking() {
        imageTrackingProvider = nil
    }
#else
    // Stubs for non-visionOS builds; keep signatures but with `Any` parameter
    func startImageTracking(provider _: Any) {}
    func stopTracking() {}
#endif
}
