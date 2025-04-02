#if os(iOS)
import ARKit
import RealityKit

/// An AR session manager for iOS that configures an ARView's session.
class ARSessionManager {
    static let shared = ARSessionManager()
    private init() { }

    /// Configures the AR session based on the selected sync mode.
    /// - Parameters:
    ///   - arView: The ARView whose session needs configuration.
    ///   - syncMode: The desired synchronization mode (.world or .imageTarget).
    ///   - referenceImages: The set of reference images to detect (only used if syncMode is .imageTarget).
    func configureSession(for arView: ARView, syncMode: SyncMode, referenceImages: Set<ARReferenceImage> = Set()) {
        print("[iOS] Configuring ARSession for mode: \(syncMode.rawValue)")
        // Always use ARWorldTrackingConfiguration as it supports both world tracking and image detection.
        let config = ARWorldTrackingConfiguration()
        
        // Basic configuration applicable to both modes
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .meshWithClassification
            print("[iOS] Scene Reconstruction enabled.")
        } else {
            print("[iOS] Scene Reconstruction not supported.")
        }
        config.environmentTexturing = .automatic
        config.isCollaborationEnabled = true // Essential for multipeer

        // Configure for Image Target mode
        if syncMode == .imageTarget {
            if referenceImages.isEmpty {
                print("[iOS] Warning: Image Target mode selected, but no reference images provided.")
                // Proceed with world tracking only, or handle error as needed
                config.detectionImages = Set() // Ensure it's empty
            } else {
                config.detectionImages = referenceImages
                // Set the maximum number of tracked images if needed (default is 1)
                config.maximumNumberOfTrackedImages = 1 // Adjust if you need to track multiple images simultaneously
                print("[iOS] Configured ARWorldTrackingConfiguration with \(referenceImages.count) detection images.")
            }
        } else {
            // Ensure detectionImages is empty for world mode
            config.detectionImages = Set()
            print("[iOS] Configured ARWorldTrackingConfiguration for World Space Sync.")
        }
        
        // Run the session with the new configuration
        // Reset tracking and remove existing anchors to apply the new settings cleanly
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        print("[iOS] ARSession run with new configuration.")
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
