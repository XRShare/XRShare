#if os(iOS)
import ARKit
import RealityKit

/// An AR session manager for iOS that configures an ARView's session.
class ARSessionManager {
    static let shared = ARSessionManager()
    private init() { }

    func configureSession(for arView: ARView) {
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .meshWithClassification
        }
        config.environmentTexturing = .automatic
        config.isCollaborationEnabled = true
        
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }
}
#elseif os(visionOS)
import SwiftUI
import RealityKit

/// A stub AR session manager for visionOS.
/// On visionOS, you use RealityView and its internal session management.
class ARSessionManager {
    static let shared = ARSessionManager()
    private init() { }

    func configureSession() {
        // No manual configuration is needed—RealityView manages its own AR session.
        print("Session configuration for visionOS is handled automatically by RealityView.")
    }
}
#endif
