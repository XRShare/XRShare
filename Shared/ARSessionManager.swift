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
    ///   - syncMode: The desired synchronization mode (.world, .imageTarget, or .objectTarget).
    ///   - referenceImages: The set of reference images to detect (only used if syncMode is .imageTarget).
    ///   - referenceObjects: The set of reference objects to detect (only used if syncMode is .objectTarget).
    func configureSession(for arView: ARView, syncMode: SyncMode, referenceImages: Set<ARReferenceImage> = Set(), referenceObjects: Set<ARReferenceObject> = Set()) {
        print("[iOS] Configuring ARSession for mode: \(syncMode.rawValue)")
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

        // Configure for Object Target mode
        if syncMode == .objectTarget {
            if referenceObjects.isEmpty {
                 print("[iOS] Warning: Object Target mode selected, but no reference objects provided.")
                 config.detectionObjects = Set() // Ensure it's empty
            } else {
                 config.detectionObjects = referenceObjects
                 print("[iOS] Configured ARWorldTrackingConfiguration with \(referenceObjects.count) detection objects.")
            }
            // Ensure detectionImages is empty for object mode
            config.detectionImages = Set()
        } else if syncMode != .imageTarget { // Ensure detectionObjects is empty if not in object mode
             config.detectionObjects = Set()
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
