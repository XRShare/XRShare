#if os(iOS)
import ARKit
import RealityKit

/// Handles ARSessionDelegate callbacks and forwards them to the ARViewModel.
/// This separation helps manage delegate responsibilities, especially with MainActor isolation.
class ARSessionDelegateHandler: NSObject, ARSessionDelegate {
    weak var arViewModel: ARViewModel?
    
    init(arViewModel: ARViewModel) {
        self.arViewModel = arViewModel
        super.init()
    }
    
    // Removed @MainActor - Delegate methods are not called on main thread
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        // Use weak self to avoid retain cycles in async blocks
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let arViewModel = self.arViewModel else { return }
            
            for anchor in anchors {
                // Handle plane anchors, image anchors, etc. if needed
                if anchor is ARPlaneAnchor {
                    // print("Plane anchor added/updated: \(anchor.identifier)")
                } else if let imageAnchor = anchor as? ARImageAnchor {
                    let imageName = imageAnchor.referenceImage.name ?? "unknown"
                    // Handle only when in image target mode
                    guard arViewModel.currentSyncMode == .imageTarget else { continue }

                    if imageAnchor.isTracked {
                        if !arViewModel.isSyncedToImage {
                            // Perform one-time sync
                            arViewModel.sharedAnchorEntity.setTransformMatrix(imageAnchor.transform, relativeTo: nil)
                            arViewModel.isSyncedToImage = true
                            arViewModel.isImageTracked = true
                            print("✅ [iOS] Image Target '\(imageName)' detected. Synced sharedAnchorEntity.")
                        } else {
                            // Already synced, just update detection status
                            if !arViewModel.isImageTracked {
                                arViewModel.isImageTracked = true
                                print("👀 [iOS] Image Target '\(imageName)' re-detected (already synced).")
                            }
                        }
                    } else {
                        // Image lost tracking (but might still exist as an anchor)
                        if arViewModel.isImageTracked {
                            arViewModel.isImageTracked = false
                            print("⚠️ [iOS] Image Target '\(imageName)' lost tracking.")
                            // Do not reset isSyncedToImage
                        }
                    }
                } else {
                     // Log other unknown anchor types if necessary
                     // print("Ignoring unknown anchor type added: \(anchor.identifier), Type: \(type(of: anchor))")
                }
            }
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        // Use weak self to avoid retain cycles in async blocks
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let arViewModel = self.arViewModel else { return }

            for anchor in anchors {
                if let imageAnchor = anchor as? ARImageAnchor {
                    let imageName = imageAnchor.referenceImage.name ?? "unknown"
                    // Handle only when in image target mode
                    guard arViewModel.currentSyncMode == .imageTarget else { continue }

                    if imageAnchor.isTracked {
                        if !arViewModel.isSyncedToImage {
                            // Perform one-time sync if detected during update
                            arViewModel.sharedAnchorEntity.setTransformMatrix(imageAnchor.transform, relativeTo: nil)
                            arViewModel.isSyncedToImage = true
                            arViewModel.isImageTracked = true
                            print("✅ [iOS] Image Target '\(imageName)' detected via update. Synced sharedAnchorEntity.")
                        } else {
                            // Already synced, just update detection status
                             if !arViewModel.isImageTracked {
                                 arViewModel.isImageTracked = true
                                 print("👀 [iOS] Image Target '\(imageName)' re-detected via update (already synced).")
                             }
                        }
                    } else {
                        // Image lost tracking
                        if arViewModel.isImageTracked {
                            arViewModel.isImageTracked = false
                            print("⚠️ [iOS] Image Target '\(imageName)' lost tracking via update.")
                            // Do not reset isSyncedToImage
                        }
                    }
                }
            }
        }
    }
    
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        // Use weak self to avoid retain cycles in async blocks
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let arViewModel = self.arViewModel else { return }
            
            for anchor in anchors {
                if let imageAnchor = anchor as? ARImageAnchor {
                     let imageName = imageAnchor.referenceImage.name ?? "unknown"
                     // Handle only when in image target mode
                     guard arViewModel.currentSyncMode == .imageTarget else { continue }

                    print("❌ [iOS] Image Target '\(imageName)' anchor removed.")
                    if arViewModel.isImageTracked {
                        arViewModel.isImageTracked = false // Mark as not detected
                        // Do not reset isSyncedToImage
                    }
                }
                // Clean up associated content if needed
                arViewModel.processedAnchorIDs.remove(anchor.identifier)
                if let index = arViewModel.placedAnchors.firstIndex(where: { $0.identifier == anchor.identifier }) {
                    arViewModel.placedAnchors.remove(at: index)
                }
                // Find RealityKit AnchorEntity associated with this ARAnchor and remove it
                // Filter anchors manually as removeAll(where:) might have signature issues
                if let scene = arViewModel.arView?.scene {
                    let anchorsToRemove = scene.anchors.filter { $0.anchorIdentifier == anchor.identifier }
                    for anchorToRemove in anchorsToRemove {
                        scene.removeAnchor(anchorToRemove)
                        print("Removed RealityKit anchor associated with ARAnchor: \(anchor.identifier)")
                    }
                }
            }
        }
    }

    // No @MainActor needed here, but access arViewModel safely if needed later
    func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
        // Access arViewModel and multipeerSession safely
        guard let viewModel = self.arViewModel, // Use self.arViewModel
              let mpSession = viewModel.multipeerSession,
              !mpSession.session.connectedPeers.isEmpty else {
            // print("Collaboration data received but no session or peers to send to.")
            return
        }
        
        // Only send if it's critical or few peers
        guard data.priority == .critical || mpSession.session.connectedPeers.count < 3 else { return }
        
        do {
            let archivedData = try NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: true)
            // Use the helper method with correct parameter order (no need for line breaks)
            // Ensure mpSession is accessed correctly
            mpSession.sendToAllPeers(archivedData, dataType: .collaborationData, reliable: true)
        } catch {
            print("Error archiving/sending collaboration data: \(error)")
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("ARSession failed: \(error.localizedDescription)")
        // Use weak self to avoid retain cycles in async blocks
        DispatchQueue.main.async { [weak self] in
            // Access arViewModel safely using self?
            self?.arViewModel?.alertItem = AlertItem(title: "AR Error", message: error.localizedDescription)
        }
    }
}
#endif
