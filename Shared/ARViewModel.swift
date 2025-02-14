#if os(iOS)
import SwiftUI
import RealityKit
import ARKit
import Combine
import MultipeerConnectivity

public enum UserRole {
    case host, viewer, openSession
}
struct Session: Identifiable {
    let sessionID: String
    let sessionName: String
    let peerID: String
    var id: String { sessionID }
}

// The iOS ARViewModel using ARKit with minimal manual functions.
class ARViewModel: NSObject, ObservableObject{
    
    // MARK: - Published Properties
    @Published var selectedModel: Model? = nil
    @Published var alertItem: AlertItem?
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isPlaneVisualizationEnabled = false
    @Published var loadingProgress: Float = 0.0
    @Published var userRole: UserRole = .openSession
    @Published var isHostPermissionGranted = false
    
    // Debug toggles
    @Published var areFeaturePointsEnabled = false { didSet { updateDebugOptions() } }
    @Published var isWorldOriginEnabled = false { didSet { updateDebugOptions() } }
    @Published var areAnchorOriginsEnabled = false { didSet { updateDebugOptions() } }
    @Published var isAnchorGeometryEnabled = false { didSet { updateDebugOptions() } }
    @Published var isSceneUnderstandingEnabled = false { didSet { updateDebugOptions() } }
    
    // Additional UI properties
    @Published var availableSessions: [Session] = []
    @Published var selectedSession: Session? = nil
    private var subscriptions = Set<AnyCancellable>()
    
    // MARK: - AR and Networking References
    weak var arView: ARView?
    var models: [Model] = []
    var placedAnchors: [ARAnchor] = []
    var anchorEntities: [UUID: AnchorEntity] = [:]
    var pendingAnchorPayloads: [UUID: AnchorTransformPayload] = [:]
    var processedAnchorIDs: Set<UUID> = []
    var anchorsAddedLocally: Set<UUID> = []
    var pendingAnchors: [UUID: ARAnchor] = [:]
    
    var multipeerSession: MultipeerSession!
    var sessionID: String = UUID().uuidString
    var sessionName: String = ""
    
    // Multipeer control
    var deferredStartMultipeerServices = false
    var shouldStartMultipeerSession = false
    
    // MARK: - Initialization
    override init() {
        super.init()
    }
    
    // MARK: - Multipeer Services Control
    func deferMultipeerServicesUntilModelsLoad() {
        deferredStartMultipeerServices = true
    }
    
    func invitePeer(_ peerID: String, sessionID: String) {
        // Implement your invitation logic here.
        print("Inviting peer \(peerID) to session \(sessionID)")
    }
    
    func togglePlaneVisualization() {
        isPlaneVisualizationEnabled.toggle()
    }
    
    func toggleHostPermissions() {
        isHostPermissionGranted.toggle()
        print("Host permissions toggled to \(isHostPermissionGranted)")
    }
    
    // MARK: - AR Session Management
    func resetARSession() {
        guard let arView = arView else { return }
        arView.session.pause()
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }
    
    // MARK: - Model Loading
    func loadModels() {
        guard models.isEmpty else { return }
        let modelTypes = ModelType.allCases()
        let totalModels = modelTypes.count
        var loadedModels = 0
        
        for mt in modelTypes {
            let model = Model(modelType: mt)
            models.append(model)
            
            model.$loadingState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    switch state {
                    case .loaded:
                        loadedModels += 1
                        self?.loadingProgress = Float(loadedModels) / Float(totalModels)
                        if loadedModels == totalModels {
                            print("All models loaded.")
                            self?.enableMultipeerServicesIfDeferred()
                        }
                    case .failed(let error):
                        self?.alertItem = AlertItem(title: "Failed to Load Model",
                                                    message: "\(mt.rawValue.capitalized): \(error.localizedDescription)")
                    default:
                        break
                    }
                }
                .store(in: &subscriptions)
        }
    }
    
    // MARK: - AR View Setup
    func setupARView(_ arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
        updateDebugOptions()
        ARSessionManager.shared.configureSession(for: arView)
        
        // Add a tap gesture recognizer.
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        if shouldStartMultipeerSession {
            startMultipeerServices()
        }
    }
    
    func updateDebugOptions() {
        var opts: ARView.DebugOptions = []
        if areFeaturePointsEnabled     { opts.insert(.showFeaturePoints) }
        if isWorldOriginEnabled        { opts.insert(.showWorldOrigin) }
        if areAnchorOriginsEnabled     { opts.insert(.showAnchorOrigins) }
        if isAnchorGeometryEnabled     { opts.insert(.showAnchorGeometry) }
        if isSceneUnderstandingEnabled { opts.insert(.showSceneUnderstanding) }
        arView?.debugOptions = opts
    }
    
    // MARK: - Multipeer Services
    func startMultipeerServices() {
        guard multipeerSession == nil else { return }
        let discoveryInfo: [String: String]? = (userRole == .host || userRole == .openSession)
            ? ["sessionID": sessionID, "sessionName": sessionName]
            : nil
        multipeerSession = MultipeerSession(sessionID: sessionID, sessionName: sessionName, discoveryInfo: discoveryInfo)
        multipeerSession.delegate = self
        multipeerSession.start()
        print("Multipeer session started with ID \(sessionID)")
    }
    
    func enableMultipeerServicesIfDeferred() {
        if shouldStartMultipeerSession {
            startMultipeerServices()
        }
    }
    
    func stopMultipeerServices() {
        multipeerSession?.stop()
        multipeerSession = nil
        print("Multipeer services stopped.")
    }
    
    // MARK: - Content Placement
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        guard userRole != .viewer || isHostPermissionGranted,
              let arView = arView,
              let model = selectedModel,
              let _ = model.modelEntity else { return }
        let location = sender.location(in: arView)
        let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)
        if let result = results.first {
            let uniqueID = UUID().uuidString
            let anchorName = "\(model.modelType.rawValue)_\(uniqueID)"
            let anchor = ARAnchor(name: anchorName, transform: result.worldTransform)
            arView.session.add(anchor: anchor)
            placedAnchors.append(anchor)
            anchorsAddedLocally.insert(anchor.identifier)
        }
    }
}

// MARK: - ARSessionDelegate
extension ARViewModel: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if processedAnchorIDs.contains(anchor.identifier) { continue }
            
            // If this is a plane anchor and plane visualization is enabled.
            if let planeAnchor = anchor as? ARPlaneAnchor, isPlaneVisualizationEnabled {
                let planeEntity = makePlaneEntity(for: planeAnchor)
                let anchorEntity = AnchorEntity()
                anchorEntity.transform = Transform(matrix: planeAnchor.transform)
                anchorEntity.addChild(planeEntity)
                arView?.scene.addAnchor(anchorEntity)
            }
            else if let _ = anchor.name {
                if anchorsAddedLocally.contains(anchor.identifier) {
                    placeModel(for: anchor)
                    processedAnchorIDs.insert(anchor.identifier)
                    anchorsAddedLocally.remove(anchor.identifier)
                    
                    if userRole == .host || isHostPermissionGranted {
                        sendAnchorWithTransform(anchor: anchor)
                    }
                }
                else if let payload = pendingAnchorPayloads[anchor.identifier] {
                    placeModel(for: anchor, modelID: payload.modelID, transformArray: payload.transform)
                    pendingAnchorPayloads.removeValue(forKey: anchor.identifier)
                    processedAnchorIDs.insert(anchor.identifier)
                }
                else {
                    // Save anchor for later processing.
                    pendingAnchors[anchor.identifier] = anchor
                }
            }
        }
    }
    
    func sendAnchorWithTransform(anchor: ARAnchor) {
        if let anchorData = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true),
           let anchorEntity = anchorEntities[anchor.identifier],
           let modelEntity = anchorEntity.children.first as? ModelEntity {
            let modelID = modelEntity.name
            let transformArray = modelEntity.transform.matrix.toArray()
            let payload = AnchorTransformPayload(anchorData: anchorData, modelID: modelID, transform: transformArray)
            do {
                let data = try JSONEncoder().encode(payload)
                multipeerSession?.sendToAllPeers(data, dataType: .modelTransform)
            } catch {
                print("Failed to encode AnchorTransformPayload: \(error)")
            }
        }
    }
    
    private func makePlaneEntity(for planeAnchor: ARPlaneAnchor) -> ModelEntity {
        let mesh = MeshResource.generatePlane(width: 0.5, depth: 0.5)
        let material = SimpleMaterial(color: .blue, isMetallic: false)
        let plane = ModelEntity(mesh: mesh, materials: [material])
        plane.name = "plane"
        return plane
    }
    
    func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
        // In this minimal implementation we simply forward collaboration data if peers are connected.
        guard let m = multipeerSession, !(m.session?.connectedPeers.isEmpty ?? true) else { return }
        do {
            let encoded = try NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: true)
            m.sendToAllPeers(encoded, dataType: .collaborationData)
        } catch {
            print("Failed to encode collaboration data: \(error)")
        }
    }
    
    // Clears all local anchors and notifies connected peers.
    func clearAllModels() {
        guard let arView = arView else { return }
        let anchorIDs = placedAnchors.map { $0.identifier }
        for anchor in placedAnchors {
            arView.session.remove(anchor: anchor)
            if let anchorEntity = anchorEntities[anchor.identifier] {
                arView.scene.removeAnchor(anchorEntity)
                anchorEntities.removeValue(forKey: anchor.identifier)
            }
        }
        placedAnchors.removeAll()
        do {
            let ids = anchorIDs.map { $0.uuidString }
            let data = try JSONEncoder().encode(ids)
            multipeerSession?.sendToAllPeers(data, dataType: .removeAnchors)
        } catch {
            print("Failed to encode anchor IDs for removal: \(error)")
        }
    }
    
    func placeModel(for anchor: ARAnchor, modelID: String? = nil, transformArray: [Float]? = nil) {
        guard let anchorName = anchor.name else { return }
        // Determine final model ID.
        let finalModelID = modelID ?? {
            let comps = anchorName.split(separator: "_", maxSplits: 1)
            return comps.count == 2 ? String(comps[1]) : UUID().uuidString
        }()
        
        let modelTypeName = String(anchorName.split(separator: "_").first ?? "")
        guard let model = models.first(where: {
            $0.modelType.rawValue.lowercased() == modelTypeName.lowercased()
        }),
        let modelEntity = model.modelEntity
        else {
            print("Model not found for anchor type \(modelTypeName)")
            return
        }
        
        let anchorEntity = AnchorEntity()
        anchorEntity.transform = Transform(matrix: anchor.transform)
        
        // Clone the model entity.
        let clone = modelEntity.clone(recursive: true)
        clone.name = finalModelID
        
        if let tarr = transformArray {
            let newMatrix = simd_float4x4.fromArray(tarr)
            clone.transform.matrix = newMatrix
        } else {
            clone.scale *= SIMD3<Float>(repeating: 0.8)
        }
        clone.generateCollisionShapes(recursive: true)
        anchorEntity.addChild(clone)
        
        arView?.scene.addAnchor(anchorEntity)
        anchorEntities[anchor.identifier] = anchorEntity
        processedAnchorIDs.insert(anchor.identifier)
    }
    
    func processPendingAnchors() {
        for (anchorID, payload) in pendingAnchorPayloads {
            if let anchor = arView?.session.currentFrame?.anchors.first(where: { $0.identifier == anchorID }) {
                placeModel(for: anchor, modelID: payload.modelID, transformArray: payload.transform)
                processedAnchorIDs.insert(anchor.identifier)
            }
        }
        pendingAnchorPayloads.removeAll()
    }
    
    // Remove all plane entities from the scene.
    func removeAllPlaneEntities() {
        guard let arView = arView else { return }
        arView.scene.anchors.forEach { anchor in
            anchor.children.forEach { ent in
                if let planeEntity = ent as? ModelEntity, planeEntity.name == "plane" {
                    anchor.removeChild(planeEntity)
                }
            }
        }
    }
}

// MARK: - MultipeerSessionDelegate
extension ARViewModel: MultipeerSessionDelegate {
    func receivedData(_ data: Data, from peerID: MCPeerID) {
        guard data.count > 1, let arView = arView else { return }
        let dataTypeByte = data.first!
        let payload = data.advanced(by: 1)
        if let dt = DataType(rawValue: dataTypeByte) {
            switch dt {
            case .collaborationData:
                do {
                    if let collabData = try NSKeyedUnarchiver.unarchivedObject(
                        ofClass: ARSession.CollaborationData.self,
                        from: payload
                    ) {
                        arView.session.update(with: collabData)
                    }
                } catch {
                    print("Failed to decode collaboration data: \(error)")
                }
            case .modelTransform:
                // Decode and apply model transform if needed.
                break
            case .removeAnchors:
                // Decode and remove anchors.
                break
            case .permissionUpdate:
                do {
                    let isGranted = try JSONDecoder().decode(Bool.self, from: payload)
                    DispatchQueue.main.async {
                        self.isHostPermissionGranted = isGranted
                    }
                } catch {
                    print("Failed to decode permission update: \(error)")
                }
            case .textMessage:
                if let message = String(data: payload, encoding: .utf8) {
                    print("Text message from \(peerID.displayName): \(message)")
                }
            case .arWorldMap:
                 break
            case .anchor:
                break
            case .anchorWithTransform:
                break
            }
        }
    }
    
    func peerDidChangeState(peerID: MCPeerID, state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                print("Connected to \(peerID.displayName)")
            case .notConnected:
                if let index = self.connectedPeers.firstIndex(of: peerID) {
                    self.connectedPeers.remove(at: index)
                }
            case .connecting:
                print("Connecting to \(peerID.displayName)")
            @unknown default:
                break
            }
        }
    }
    
    func didReceiveInvitation(from peerID: MCPeerID, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, multipeerSession.session)
    }
    
    func foundPeer(peerID: MCPeerID, sessionID: String, sessionName: String) {
        DispatchQueue.main.async {
            if !self.connectedPeers.contains(peerID) {
                print("Found peer \(peerID.displayName)")
            }
        }
    }
    
    func lostPeer(peerID: MCPeerID) {
        DispatchQueue.main.async {
            if let index = self.connectedPeers.firstIndex(of: peerID) {
                self.connectedPeers.remove(at: index)
            }
        }
    }
}

#elseif os(visionOS)
import SwiftUI
import RealityKit
import Combine
import MultipeerConnectivity

public enum UserRole {
    case host, viewer, openSession
}

/// A stub ARViewModel for visionOS that excludes ARKit‐specific code.
/// On visionOS, RealityView manages the AR session automatically.
class ARViewModel: ObservableObject {
    @Published var selectedModel: Model? = nil
    @Published var alertItem: AlertItem?
    @Published var connectedPeers: [MCPeerID] = []
    @Published var loadingProgress: Float = 0.0
    @Published var userRole: UserRole = .openSession
    @Published var isHostPermissionGranted = false
    
    var models: [Model] = []
    var cancellables = Set<AnyCancellable>()
    
    /// visionOS does not use ARView or ARAnchor.
    /// Provide a stub setup method for RealityView.
    func setupAR() {
        print("On visionOS, AR session configuration is handled automatically by RealityView.")
    }
    
    func loadModels() {
        guard models.isEmpty else { return }
        let modelTypes = ModelType.allCases()
        let totalModels = modelTypes.count
        var loadedModels = 0
        
        for mt in modelTypes {
            let model = Model(modelType: mt)
            models.append(model)
            
            model.$loadingState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    switch state {
                    case .loaded:
                        loadedModels += 1
                        self?.loadingProgress = Float(loadedModels) / Float(totalModels)
                        if loadedModels == totalModels {
                            print("All models loaded.")
                        }
                    case .failed(let error):
                        self?.alertItem = AlertItem(title: "Failed to Load Model",
                                                     message: "\(mt.rawValue.capitalized): \(error.localizedDescription)")
                    default:
                        break
                    }
                }
                .store(in: &cancellables)
        }
    }
}
#endif
