#if os(iOS)
import SwiftUI
import RealityKit
import ARKit
import Combine
import MultipeerConnectivity

public enum UserRole {
    case host, viewer, openSession
}

/// Simple struct for displaying peers you discover.
struct Session: Identifiable, Hashable {
    let sessionID: String
    let sessionName: String
    let peerID: MCPeerID
    var id: String { sessionID }
}

// MARK: - ARViewModel

class ARViewModel: NSObject, ObservableObject {
    // Published properties
    @Published var selectedModel: Model? = nil
    @Published var alertItem: AlertItem?
    @Published var loadingProgress: Float = 0.0
    @Published var userRole: UserRole = .openSession
    @Published var isHostPermissionGranted = false
    @Published var selectedSession: Session? = nil
    @Published var connectedPeers: [MCPeerID] = []
    
    // Debug toggles
    @Published var isPlaneVisualizationEnabled: Bool = false
    @Published var areFeaturePointsEnabled: Bool = false
    @Published var isWorldOriginEnabled: Bool = false
    @Published var areAnchorOriginsEnabled: Bool = false
    @Published var isAnchorGeometryEnabled: Bool = false
    @Published var isSceneUnderstandingEnabled: Bool = false
    
    // New: availableSessions for the startup menu
    @Published var availableSessions: [Session] = []
    
    // AR & Model references
    weak var arView: ARView?
    var models: [Model] = []
    
    // Networking
    var multipeerSession: MultipeerSession!
    var sessionID: String = UUID().uuidString
    var sessionName: String = ""
    
    // Deferred multipeer flag
    private var deferredMultipeer: Bool = false
    
    private var subscriptions = Set<AnyCancellable>()
    
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
            
            // Track loading progress
            model.$loadingState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    if case .loaded = state {
                        loadedCount += 1
                        self?.loadingProgress = Float(loadedCount) / Float(modelTypes.count)
                        if loadedCount == modelTypes.count {
                            print("All models loaded.")
                        }
                    }
                }
                .store(in: &subscriptions)
        }
    }
    
    // MARK: - AR Setup
    
    func setupARView(_ arView: ARView) {
        self.arView = arView
        
        // Configure ARKit for plane detection + collaboration
        ARSessionManager.shared.configureSession(for: arView)
        
        // Start your custom MC session
        startMultipeerServices()
        
        // Attach RealityKit’s built-in sync service
        if let mpSession = multipeerSession {
            do {
                let syncService = try MultipeerConnectivityService(session: mpSession.session)
                arView.scene.synchronizationService = syncService
            } catch {
                print("Error creating sync service: \(error)")
            }
        }
        
        // Add a tap gesture for model placement
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Tap to Place Model
    
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard
                let arView = arView,
                let modelEntity = selectedModel?.modelEntity
            else { return }
            
            let tapPoint = sender.location(in: arView)
            let results = arView.raycast(
                from: tapPoint,
                allowing: .estimatedPlane,
                alignment: .any
            )
            guard let firstResult = results.first else { return }
            
            // Create an AnchorEntity at the raycast location
            let anchorEntity = AnchorEntity(raycastResult: firstResult)
            
            // Clone & add the selected model to the anchor
            let newEntity = modelEntity.clone(recursive: true)
            anchorEntity.addChild(newEntity)
            
            // Ensure collisions so gestures can work
            newEntity.generateCollisionShapes(recursive: true)
            
            // Install built-in translation, rotation, and scaling gestures
            arView.installGestures([.translation, .rotation, .scale], for: newEntity)
            
            // Add anchor to the scene (auto-syncs to peers)
            arView.scene.addAnchor(anchorEntity)
        }

    // MARK: - Networking
    
    func startMultipeerServices() {
        // If we already have a session, do nothing
        guard multipeerSession == nil else { return }
        
        // Only set discoveryInfo if userRole is host or openSession
        let discoveryInfo = (userRole == .host||userRole == .openSession)
            ? ["sessionID": sessionID, "sessionName": sessionName]
            : nil
        
        multipeerSession = MultipeerSession(
            sessionID: sessionID,
            sessionName: sessionName,
            discoveryInfo: discoveryInfo
        )
        multipeerSession.delegate = self
        multipeerSession.start()
        print("Multipeer session started: \(sessionID)")
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
    
    // MARK: - AR Session Control
    
    func resetARSession() {
        guard let arView = arView else { return }
        
        arView.session.pause()
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.isCollaborationEnabled = true
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }
    
    func toggleHostPermissions() {
        isHostPermissionGranted.toggle()
        print("Host permissions toggled to \(isHostPermissionGranted)")
    }
    
    // If you want to remove all placed models:
    func clearAllModels() {
        guard let arView = arView else { return }
        
        // Remove all AnchorEntities from the scene
        for anchor in arView.scene.anchors {
            anchor.removeFromParent()
        }
        print("Cleared all models (removed all anchors).")
    }
}

// MARK: - ARSessionDelegate
extension ARViewModel: ARSessionDelegate {
    // We do not manually ship ARSession.CollaborationData anymore,
    // because RealityKit's MultipeerConnectivityService handles anchor sync automatically.
    // If you still want to share environment mesh, keep isCollaborationEnabled but
    // remove your old manual data sending code.
    //
    // You can keep these stubs empty unless you do something else with them:

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // e.g., handle frame updates if you want
    }
}

// MARK: - MultipeerSessionDelegate
extension ARViewModel: MultipeerSessionDelegate {
    // If you want to handle custom data from peers, do it here:
    func receivedData(_ data: Data, from peerID: MCPeerID) {
        // No-op by default, or handle text chat, etc.
        print("Received custom data of size \(data.count) from \(peerID.displayName).")
    }
    
    func peerDidChangeState(peerID: MCPeerID, state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
            case .notConnected:
                if let index = self.connectedPeers.firstIndex(of: peerID) {
                    self.connectedPeers.remove(at: index)
                }
            default:
                break
            }
            print("Peer \(peerID.displayName) state: \(state)")
        }
    }
    
    func didReceiveInvitation(from peerID: MCPeerID,
                             invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        if userRole == .host {
            // I'm the host, so I expect viewers to join me. I accept.
            invitationHandler(true, multipeerSession.session)
        } else {
            // I'm a viewer, so accept if we want that scenario, or check sessionIDs if you only
            // want to connect to a certain one.
            invitationHandler(true, multipeerSession.session)
        }
    }
    
    func foundPeer(peerID: MCPeerID, sessionID: String, sessionName: String) {
        DispatchQueue.main.async {
            // Append discovered peers to our list
            let newSession = Session(
                sessionID: sessionID,
                sessionName: sessionName,
                peerID: peerID
            )
            self.availableSessions.append(newSession)
            print("Found peer: \(peerID.displayName)")
        }
    }
    
    func lostPeer(peerID: MCPeerID) {
        DispatchQueue.main.async {
            if let index = self.availableSessions.firstIndex(where: { $0.peerID == peerID }) {
                self.availableSessions.remove(at: index)
            }
            print("Lost peer: \(peerID.displayName)")
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
