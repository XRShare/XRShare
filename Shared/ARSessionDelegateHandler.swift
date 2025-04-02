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
                    print("Image anchor detected: \(imageAnchor.referenceImage.name ?? "unknown")")
                    // Update shared anchor transform based on image anchor
                    // Access arViewModel properties safely within the main queue block
                    arViewModel.sharedAnchorEntity.setTransformMatrix(imageAnchor.transform, relativeTo: nil)
                    arViewModel.isImageTracked = imageAnchor.isTracked // Update tracking status
                    
                    // If sync mode is image target, notify that the anchor is found
                    if arViewModel.currentSyncMode == .imageTarget {
                        // Potentially trigger synchronization of models relative to this anchor
                        print("Image anchor added/updated in Image Target mode.")
                    }
                // Removed handling for user-placed anchors (arViewModel.placedAnchors)
                // Placement is now handled directly in ARViewModel.handleTap
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
                    // Update shared anchor transform and tracking status
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
        // Use weak self to avoid retain cycles in async blocks
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let arViewModel = self.arViewModel else { return }
            
            for anchor in anchors {
                if let imageAnchor = anchor as? ARImageAnchor {
                    print("Image anchor removed: \(imageAnchor.referenceImage.name ?? "unknown")")
                    if arViewModel.isImageTracked {
                        arViewModel.isImageTracked = false // Mark as not tracked
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
