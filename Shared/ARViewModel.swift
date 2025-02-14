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

/// The iOS version of ARViewModel that uses ARKit.
class ARViewModel: NSObject, ObservableObject, ARSessionDelegate {
    
    // MARK: - Published properties
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

    // -- Add these missing properties if your UI references them
    @Published var availableSessions: [Session] = []
    @Published var selectedSession: Session? = nil          
    private var subscriptions = Set<AnyCancellable>()
    
    // MARK: - AR and Networking references
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
    
    // Add these if your UI calls them
    var deferredStartMultipeerServices = false
    var shouldStartMultipeerSession = false

    // Keep track if you need to wait until models are loaded
    // (depending on your code flow):
    func deferMultipeerServicesUntilModelsLoad() {
        self.deferredStartMultipeerServices = true
    }
    // Example properties that you reference in your view:
//        var sessionID: String = ""
//        var sessionName: String = ""
//        var userRole: UserRole = .viewer
        
        // Define invitePeer as a function.
        func invitePeer(_ peerID: String, sessionID: String) {
            // Your implementation here.
            print("Inviting peer \(peerID) to session \(sessionID)")
        }
    // A toggle function your UI might call
    func togglePlaneVisualization() {
        isPlaneVisualizationEnabled.toggle()
    }
    func toggleHostPermissions() {
            isHostPermissionGranted.toggle()
            print("Host permissions toggled to \(isHostPermissionGranted)")
        }
    // Called by UI to reset the AR session
    func resetARSession() {
        guard let arView = arView else { return }
        
        // Example reset:
        arView.session.pause()
        // Possibly re-run session with new configuration
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
    
    // MARK: - AR Setup (iOS)
    func setupARView(_ arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
        updateDebugOptions()
        ARSessionManager.shared.configureSession(for: arView)
        
        // Add gesture recognizer (iOS only)
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        if shouldStartMultipeerSession {
            startMultipeerServices()
        }
    }
    
    func updateDebugOptions() {
        var opts: ARView.DebugOptions = []
        if areFeaturePointsEnabled       { opts.insert(.showFeaturePoints) }
        if isWorldOriginEnabled          { opts.insert(.showWorldOrigin) }
        if areAnchorOriginsEnabled       { opts.insert(.showAnchorOrigins) }
        if isAnchorGeometryEnabled       { opts.insert(.showAnchorGeometry) }
        if isSceneUnderstandingEnabled   { opts.insert(.showSceneUnderstanding) }
        arView?.debugOptions = opts
    }
    
    // MARK: - Multipeer Services (iOS)
    func startMultipeerServices() {
        guard multipeerSession == nil else { return }
        let discoveryInfo: [String: String]? = (userRole == .host || userRole == .openSession)
            ? ["sessionID": sessionID, "sessionName": sessionName]
            : nil
        multipeerSession = MultipeerSession(sessionID: sessionID,
                                            sessionName: sessionName,
                                            discoveryInfo: discoveryInfo)
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
    
    // MARK: - Content Placement (iOS)
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
    
    func clearAllModels() {
        guard let arView = arView else { return }
        let anchorIDs = placedAnchors.map { $0.identifier }
        for anchor in placedAnchors {
            arView.session.remove(anchor: anchor)
            if let ae = anchorEntities[anchor.identifier] {
                arView.scene.removeAnchor(ae)
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
}

// MARK: - MultipeerSessionDelegate (iOS)
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
                // Decode and apply model transform as needed.
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
            default:
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

/// A stub ARViewModel for visionOS that excludes ARKit-specific code.
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
    
    // visionOS does not use ARView or ARAnchor.
    // Provide a stub setup method for RealityView.
    func setupAR() {
        print("On visionOS, AR session configuration is handled automatically by RealityView.")
    }
    
    func loadModels() {
        guard models.isEmpty else { return }
        let modelTypes = ModelType.allCases()
        let totalModels = modelTypes.count
        var loadedModels = 0
        var cancellables = Set<AnyCancellable>()
        
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
