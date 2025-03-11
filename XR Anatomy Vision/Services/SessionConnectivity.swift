import RealityKit
import ARKit
import MultipeerConnectivity
import _RealityKit_SwiftUI

/// Handles anchor management, HUD positioning, and transform broadcast
final class SessionConnectivity: ObservableObject {
    
    func addAnchorsIfNeeded(headAnchor: AnchorEntity,
                            modelAnchor: AnchorEntity,
                            content: RealityViewContent) {
        if headAnchor.parent == nil {
            content.add(headAnchor)
        }
        if modelAnchor.parent == nil {
            content.add(modelAnchor)
        }
    }
    
    func setupHUD(_ hudEntity: Entity, headAnchor: AnchorEntity) {
        hudEntity.setPosition([0, 0.2, -1], relativeTo: headAnchor)
        if hudEntity.parent == nil {
            headAnchor.addChild(hudEntity)
        }
    }
    
    // MARK: - Broadcasting Transform
    
    func broadcastTransformIfNeeded(entity: Entity, arViewModel: ARViewModel) {
        if let customService = arViewModel.currentScene?.synchronizationService as? MyCustomConnectivityService {
            let localPointer: __PeerIDRef = customService.__toCore(peerID: customService.localPeerIdentifier)
            if let owner = customService.owner(of: entity) as? CustomPeerID,
               let localOwner = customService.__fromCore(peerID: localPointer) as? CustomPeerID,
               owner == localOwner {
                broadcastTransform(entity, arViewModel: arViewModel)
            }
        }
    }
    
    private func broadcastTransform(_ entity: Entity, arViewModel: ARViewModel) {
        let matrixArray = entity.transform.matrix.toArray()
        
        var data = Data()
        let idString = "\(entity.id)"
        if let idData = idString.data(using: .utf8) {
            var length = UInt8(idData.count)
            data.append(&length, count: 1)
            data.append(idData)
        }
        matrixArray.withUnsafeBufferPointer { buffer in
            data.append(Data(buffer: buffer))
        }
        var packet = Data([DataType.modelTransform.rawValue])
        packet.append(data)
        
        arViewModel.multipeerSession.sendToAllPeers(packet, dataType: .modelTransform)
        print("Broadcasted transform for entity \(entity.id)")
    }
}
