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
    
    @MainActor func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard let arViewModel = arViewModel else { return }
        for anchor in anchors {
            // Handle plane anchors, image anchors, etc. if needed
            if anchor is ARPlaneAnchor {
                // print("Plane anchor added/updated: \(anchor.identifier)")
            } else if let imageAnchor = anchor as? ARImageAnchor {
                print("Image anchor detected: \(imageAnchor.referenceImage.name ?? "unknown")")
                // Update shared anchor transform based on image anchor
                DispatchQueue.main.async {
                    arViewModel.sharedAnchorEntity.setTransformMatrix(imageAnchor.transform, relativeTo: nil)
                    arViewModel.isImageTracked = imageAnchor.isTracked // Update tracking status
                    
                    // If sync mode is image target, notify that the anchor is found
                    if arViewModel.currentSyncMode == .imageTarget {
                        // Potentially trigger synchronization of models relative to this anchor
                    }
                }
            } else if anchor.name != nil {
                // Handle named anchors placed by the app (if still used)
                arViewModel.placeModel(for: anchor)
            }
        }
    }
    
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
         guard let arViewModel = arViewModel else { return }
         for anchor in anchors {
             if let imageAnchor = anchor as? ARImageAnchor {
                 // Update shared anchor transform and tracking status
                 DispatchQueue.main.async {
                     if imageAnchor.isTracked {
                         arViewModel.sharedAnchorEntity.setTransformMatrix(imageAnchor.transform, relativeTo: nil)
                     }
                     // Only update state if it changed
                     if arViewModel.isImageTracked != imageAnchor.isTracked {
                         arViewModel.isImageTracked = imageAnchor.isTracked
                         print("Image anchor tracking status changed: \(arViewModel.isImageTracked)")
                     }
                 }
             }
         }
    }
    
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        guard let arViewModel = arViewModel else { return }
        for anchor in anchors {
            if let imageAnchor = anchor as? ARImageAnchor {
                print("Image anchor removed: \(imageAnchor.referenceImage.name ?? "unknown")")
                DispatchQueue.main.async {
                    if arViewModel.isImageTracked {
                        arViewModel.isImageTracked = false // Mark as not tracked
                    }
                }
            }
            // Clean up associated content if needed
            DispatchQueue.main.async {
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
                    }
                }
            }
        }
    }

    func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
        guard let arViewModel = arViewModel,
              let mpSession = arViewModel.multipeerSession,
              !mpSession.session.connectedPeers.isEmpty else { return }
        
        // Only send if it's critical or few peers
        guard data.priority == .critical || mpSession.session.connectedPeers.count < 3 else { return }
        
        do {
            let archivedData = try NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: true)
            // Verify mpSession type (for debugging, won't fix compile error directly)
            // print("Type of mpSession: \(type(of: mpSession))") // Should print Optional<MultipeerSession> or MultipeerSession
            
            // Use the helper method with correct parameter order (no need for line breaks)
            mpSession.sendToAllPeers(archivedData, dataType: .collaborationData, reliable: true)
        } catch {
            print("Error archiving/sending collaboration data: \(error)")
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("ARSession failed: \(error.localizedDescription)")
        DispatchQueue.main.async {
            self.arViewModel?.alertItem = AlertItem(title: "AR Error", message: error.localizedDescription)
        }
    }
}
#endif
