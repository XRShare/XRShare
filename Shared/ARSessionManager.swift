#if os(iOS)
import ARKit
import RealityKit

/// An AR session manager for iOS that configures an ARView's session.
class ARSessionManager {
    static let shared = ARSessionManager()
    private init() { }

    /// Configures the AR session based on the selected sync mode or local mode.
    /// - Parameters:
    ///   - arView: The ARView whose session needs configuration.
    ///   - syncMode: The desired synchronization mode (.imageTarget) or nil for local mode.
    ///   - referenceImages: The set of reference images to detect (only used if syncMode is .imageTarget).
    ///   - referenceObjects: The set of reference objects to detect (not used anymore).
    ///   - initialWorldMap: An optional ARWorldMap to restore the session.
    func configureSession(for arView: ARView,
                          syncMode: SyncMode? = nil,
                          referenceImages: Set<ARReferenceImage> = Set(),
                          referenceObjects: Set<ARReferenceObject> = Set(),
                          initialWorldMap: ARWorldMap? = nil) {
        if let syncMode = syncMode {
            print("[iOS] Configuring ARSession for mode: \(syncMode.rawValue)")
        } else {
            print("[iOS] Configuring ARSession for local mode (no sync)")
        }
        // Use ARWorldTrackingConfiguration as it supports world tracking, image detection, and object detection.
        let config = ARWorldTrackingConfiguration()

        // Basic configuration applicable to all modes
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .meshWithClassification
            print("[iOS] Scene Reconstruction enabled.")
        } else {
            print("[iOS] Scene Reconstruction not supported.")
        }
        config.environmentTexturing = .automatic
        config.isCollaborationEnabled = true // Essential for multipeer
        // If provided, restore from a saved world map
        if let worldMap = initialWorldMap {
            config.initialWorldMap = worldMap
            print("[iOS] Restoring session with provided ARWorldMap.")
        }

        // Enable Occlusion based on device capabilities
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
            print("[iOS] Enabled Person Segmentation with Depth for Occlusion.")
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
             // Fallback for devices with LiDAR but maybe not person segmentation? (Less common)
             config.frameSemantics.insert(.sceneDepth)
             print("[iOS] Enabled Scene Depth for Occlusion (Fallback).")
        } else {
            print("[iOS] Occlusion not supported or enabled on this device.")
        }


        // Configure based on mode
        if syncMode != nil {
            // Image Target mode
            if referenceImages.isEmpty {
                print("[iOS] Warning: No reference images provided for Image Target mode.")
                config.detectionImages = Set()
            } else {
                config.detectionImages = referenceImages
                config.maximumNumberOfTrackedImages = 1
                print("[iOS] Configured ARWorldTrackingConfiguration with \(referenceImages.count) detection images.")
            }
        } else {
            // Local mode - no image detection needed
            config.detectionImages = Set()
            print("[iOS] Local mode - no image detection configured.")
        }
        
        // Always clear detection objects since we only support image tracking
        config.detectionObjects = Set()


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
