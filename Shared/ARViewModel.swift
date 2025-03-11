import SwiftUI
import Combine
import MultipeerConnectivity
import RealityKit

#if os(iOS)
import ARKit
#endif

// Basic roles.
public enum UserRole {
    case host, viewer, openSession
}

/// Represents a discovered session.
struct Session: Identifiable, Hashable {
    let sessionID: String
    let sessionName: String
    let peerID: MCPeerID
    var id: String { sessionID }
}

/// A single ARViewModel for both iOS (ARView) and visionOS (RealityView).
class ARViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var selectedModel: Model? = nil
    @Published var alertItem: AlertItem?
    @Published var loadingProgress: Float = 0.0
    @Published var userRole: UserRole = .openSession
    @Published var isHostPermissionGranted = false
    @Published var selectedSession: Session? = nil
    @Published var connectedPeers: [MCPeerID] = []
    
    // Debug toggles.
    @Published var isPlaneVisualizationEnabled: Bool = false
    @Published var areFeaturePointsEnabled: Bool = false
    @Published var isWorldOriginEnabled: Bool = false
    @Published var areAnchorOriginsEnabled: Bool = false
    @Published var isAnchorGeometryEnabled: Bool = false
    @Published var isSceneUnderstandingEnabled: Bool = false
    @Published var hostedModels: [Model] = [] 
    
    // List of discovered sessions.
    @Published var availableSessions: [Session] = []
    
    // Loaded models (the `.usdz` files you discovered).
    var models: [Model] = []
    
    // Multi-peer networking references.
    var multipeerSession: MultipeerSession!
    var sessionID: String = UUID().uuidString
    var sessionName: String = ""
    
    // If we want to wait until models finish loading before starting multi-peer:
    private var deferredMultipeer: Bool = false
    
    // For Combine subscriptions to each model's load state.
    private var subscriptions = Set<AnyCancellable>()
    
    // The current RealityKit scene (only on visionOS via RealityView).
    @Published var currentScene: RealityKit.Scene?
    
    // iOS:
    #if os(iOS)
    weak var arView: ARView?
    #endif

    override init() {
        super.init()
    }
    
    // MARK: - Model Loading
    func loadModels() {
        guard models.isEmpty else { return }
        let modelTypes = ModelType.allCases()
        var loadedCount = 0
        
        for mt in modelTypes {
            let model = Model(modelType: mt)
            models.append(model)
            
            model.$loadingState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    if case .loaded = state {
                        loadedCount += 1
                        self?.loadingProgress = Float(loadedCount) / Float(modelTypes.count)
                        if loadedCount == modelTypes.count {
                            print("All models loaded.")
                        }
                    } else if case .failed(let error) = state {
                        self?.alertItem = AlertItem(title: "Model Load Failed",
                                                    message: error.localizedDescription)
                    }
                }
                .store(in: &subscriptions)
        }
    }
    
    // MARK: - iOS Setup
    #if os(iOS)
    func setupARView(_ arView: ARView) {
        self.arView = arView
        ARSessionManager.shared.configureSession(for: arView)
        
        // Start multipeer if not deferred:
        startMultipeerServices()
        
        // If you want to attach the built-in MC sync service (for iOS):
        if let mpSession = multipeerSession {
            do {
                let syncService = try RealityKit.MultipeerConnectivityService(session: mpSession.session)
                arView.scene.synchronizationService = syncService
            } catch {
                print("Error creating built-in sync service: \(error)")
            }
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
    }
    
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        guard
            let arView = arView,
            let modelEntity = selectedModel?.modelEntity
        else { return }
        
        let tapPoint = sender.location(in: arView)
        let results = arView.raycast(from: tapPoint, allowing: .estimatedPlane, alignment: .any)
        guard let firstResult = results.first else { return }
        
        let anchorEntity = AnchorEntity(raycastResult: firstResult)
        let newEntity = modelEntity.clone(recursive: true)
        anchorEntity.addChild(newEntity)
        newEntity.generateCollisionShapes(recursive: true)
        
        // ARView install gestures.
        arView.installGestures([.translation, .rotation, .scale], for: newEntity)
        
        // Add anchor to scene.
        arView.scene.addAnchor(anchorEntity)
    }
    #endif
    
    // MARK: - visionOS Setup
    #if os(visionOS)
    func setupAR() {
        // On visionOS, the RealityView handles the AR session automatically.
        print("visionOS: AR session is managed by RealityView.")
    }
    #endif
    
    // MARK: - Multi-Peer Networking
    func startMultipeerServices() {
        // If already started, do nothing:
        guard multipeerSession == nil else { return }
        
        // Use discovery info if user is host or openSession:
        let discoveryInfo = (userRole == .host || userRole == .openSession)
            ? ["sessionID": sessionID, "sessionName": sessionName]
            : nil
        
        multipeerSession = MultipeerSession(
            sessionID: sessionID,
            sessionName: sessionName,
            discoveryInfo: discoveryInfo
        )
        multipeerSession.delegate = self
        multipeerSession.start()
        
        print("Multipeer session started: ID=\(sessionID)")
    }
    
    func stopMultipeerServices() {
        multipeerSession?.stop()
        multipeerSession = nil
        print("Multipeer services stopped.")
    }
    
    func invitePeer(_ session: Session) {
        print("Inviting peer \(session.peerID) to session \(session.sessionID)")
        multipeerSession.invitePeer(session.peerID, sessionID: session.sessionID)
    }
    
    func deferMultipeerServicesUntilModelsLoad() {
        deferredMultipeer = true
    }
    
    func enableMultipeerServicesIfDeferred() {
        if deferredMultipeer {
            startMultipeerServices()
            deferredMultipeer = false
        }
    }
    
    // MARK: - AR Session Control (iOS)
    #if os(iOS)
    func resetARSession() {
        guard let arView = arView else { return }
        arView.session.pause()
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.isCollaborationEnabled = true
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }
    #endif
    
    func toggleHostPermissions() {
        isHostPermissionGranted.toggle()
        print("Host permissions toggled to \(isHostPermissionGranted)")
    }
    
    func clearAllModels() {
        #if os(iOS)
        guard let arView = arView else { return }
        for anchor in arView.scene.anchors {
            anchor.removeFromParent()
        }
        #else
        // On visionOS, you'd remove from the RealityView’s scene.
        // If you’re storing references, remove them from customSyncService, etc.
        print("visionOS: Remove anchors from RealityView and from the custom sync service.")
        #endif
        print("Cleared all models.")
    }
}

// MARK: - MultipeerSessionDelegate
extension ARViewModel: MultipeerSessionDelegate {
    func receivedData(_ data: Data, from peerID: MCPeerID) {
        guard let dataTypeByte = data.first,
              let dataType = DataType(rawValue: dataTypeByte)
        else { return }
        
        _ = data.dropFirst()
        switch dataType {
//        case .modelTransform:
//            handleModelTransform(payload, from: peerID)
        default:
            print("Received data of type \(dataType) from \(peerID.displayName)")
        }
    }
    
    /// Example handler for a broadcasted “model transform” packet.
//    func handleModelTransform(_ payload: Data, from peerID: MCPeerID) {
//        // The first byte is the length of the entity’s ID string.
//        guard payload.count >= 1 else { return }
//        let idLength = Int(payload.first!)
//        
//        // We then expect that many bytes of the ID, plus 16 floats.
//        let expectedBytes = 1 + idLength + 16 * MemoryLayout<Float>.size
//        guard payload.count >= expectedBytes else { return }
//        
//        // Extract the entity’s ID string.
//        let idData = payload.dropFirst(1).prefix(idLength)
//        guard let idString = String(data: idData, encoding: .utf8) else { return }
//        
//        // The remainder is the 16 floats of the matrix.
//        let transformData = payload.dropFirst(1 + idLength)
//        let floatCount = transformData.count / MemoryLayout<Float>.size
//        guard floatCount == 16 else { return }
//        
//        let transformArray = transformData.withUnsafeBytes {
//            Array(UnsafeBufferPointer<Float>(
//                start: $0.baseAddress?.assumingMemoryBound(to: Float.self),
//                count: 16
//            ))
//        }
//        
////        // Now locate the corresponding entity in MyCustomSyncService by matching string IDs:
////        guard let scene = currentScene,
////              let customService = scene.synchronizationService as? MyCustomSyncService
////        else { return }
////        
////        var targetEntity: Entity?
////        for (entityID, entity) in customService.registeredEntities {
////            if "\(entityID)" == idString {
////                targetEntity = entity
////                break
////            }
////        }
//        
//        // Update its transform if found:
//        if let entity = targetEntity {
//            entity.transform.matrix = simd_float4x4.fromArray(transformArray)
//            print("Applied transform update for entity \(entity.id) from peer \(peerID.displayName).")
//        }
//    }
    
    func peerDidChangeState(peerID: MCPeerID, state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
            case .notConnected:
                if let idx = self.connectedPeers.firstIndex(of: peerID) {
                    self.connectedPeers.remove(at: idx)
                }
            default:
                break
            }
            print("Peer \(peerID.displayName) is now \(state).")
        }
    }
    
    func didReceiveInvitation(from peerID: MCPeerID,
                              invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // For a host or open session, auto-accept. If you want user prompts, do so here.
        invitationHandler(true, multipeerSession.session)
    }
    
    func foundPeer(peerID: MCPeerID, sessionID: String, sessionName: String) {
        DispatchQueue.main.async {
            let newSession = Session(sessionID: sessionID, sessionName: sessionName, peerID: peerID)
            self.availableSessions.append(newSession)
            print("Found peer: \(peerID.displayName) for session \(sessionName)")
        }
    }
    
    func lostPeer(peerID: MCPeerID) {
        DispatchQueue.main.async {
            if let idx = self.availableSessions.firstIndex(where: { $0.peerID == peerID }) {
                self.availableSessions.remove(at: idx)
            }
            print("Lost peer: \(peerID.displayName)")
        }
    }
}


extension ARViewModel {
    
    /// Sends the transform of the given entity to all connected peers.
    func sendTransform(for entity: Entity) {
        // Convert the entity’s transform matrix to an array of 16 Floats.
        let matrixArray = entity.transform.matrix.toArray()  // Requires an extension to convert matrix to [Float]
        
        // Encode the entity's id as a string.
        let idString = "\(entity.id)"
        guard let idData = idString.data(using: .utf8) else {
            print("Failed to encode entity id.")
            return
        }
        
        // Build a packet:
        // 1. Append a single byte indicating the length of the id.
        var packetData = Data()
        var idLength = UInt8(idData.count)
        packetData.append(&idLength, count: 1)
        
        // 2. Append the id data.
        packetData.append(idData)
        
        // 3. Append the transform matrix (16 floats).
        matrixArray.withUnsafeBufferPointer { buffer in
            packetData.append(Data(buffer: buffer))
        }
        
        // Prepend a header byte for the data type (modelTransform).
        var fullPacket = Data([DataType.modelTransform.rawValue])
        fullPacket.append(packetData)
        
        // Send the packet via your multipeer session.
        multipeerSession.sendToAllPeers(fullPacket, dataType: .modelTransform)
        print("Sent transform for entity \(entity.id)")
    }
    
    /// Decodes an incoming transform packet and applies the update to the corresponding model.
    func handleReceivedTransform(_ data: Data, from peerID: MCPeerID) {
        // Remove the first byte (data type header).
        let packet = data.dropFirst()
        guard packet.count >= 1, let idLengthByte = packet.first else { return }
        let idLength = Int(idLengthByte)
        
        // Ensure the packet contains enough bytes for the id.
        guard packet.count >= 1 + idLength else { return }
        let idData = packet.subdata(in: 1 ..< (1 + idLength))
        guard let idString = String(data: idData, encoding: .utf8) else {
            print("Failed to decode entity id from packet.")
            return
        }
        
        // The remainder of the packet should be the transform matrix (16 floats).
        let matrixDataStart = 1 + idLength
        let matrixData = packet.subdata(in: matrixDataStart..<packet.count)
        let expectedByteCount = 16 * MemoryLayout<Float>.size
        guard matrixData.count == expectedByteCount else {
            print("Unexpected matrix data size: \(matrixData.count) bytes")
            return
        }
        
        // Decode the array of 16 floats.
        let floatArray: [Float] = matrixData.withUnsafeBytes { pointer in
            Array(UnsafeBufferPointer<Float>(
                start: pointer.bindMemory(to: Float.self).baseAddress,
                count: 16
            ))
        }
        
        // Reconstruct the simd_float4x4 matrix.
        let newMatrix = simd_float4x4(
            SIMD4(floatArray[0],  floatArray[1],  floatArray[2],  floatArray[3]),
            SIMD4(floatArray[4],  floatArray[5],  floatArray[6],  floatArray[7]),
            SIMD4(floatArray[8],  floatArray[9],  floatArray[10], floatArray[11]),
            SIMD4(floatArray[12], floatArray[13], floatArray[14], floatArray[15])
        )
        
        // Find and update the model matching this id.
        DispatchQueue.main.async {

            self.selectedModel?.modelEntity?.transform.matrix = newMatrix
        print("Updated model \(idString) transform from peer \(peerID.displayName)")
           
        }
    }
}
