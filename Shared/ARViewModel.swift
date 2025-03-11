import SwiftUI
import Combine
import MultipeerConnectivity
import RealityKit

#if os(iOS)
import ARKit
#endif

/// User roles in the application
public enum UserRole: String, Codable {
    case host = "host"
    case viewer = "viewer"
    case openSession = "open"
}

/// Represents a discovered multipeer session
struct Session: Identifiable, Hashable {
    let sessionID: String
    let sessionName: String
    let peerID: MCPeerID
    var id: String { sessionID }
}


/// Main view model for AR/XR functionality
class ARViewModel: NSObject, ObservableObject {
    
    // MARK: - Published properties
    @Published var selectedModel: Model? = nil
    @Published var alertItem: AlertItem?
    @Published var loadingProgress: Float = 0.0
    @Published var userRole: UserRole = .openSession
    @Published var isHostPermissionGranted = false
    @Published var selectedSession: Session? = nil
    @Published var connectedPeers: [MCPeerID] = []
    @Published var availableSessions: [Session] = []
    
    // iOS ARKit references
    #if os(iOS)
    weak var arView: ARView?
    var placedAnchors: [ARAnchor] = []
    var processedAnchorIDs: Set<UUID> = []
    #endif
    
    // RealityKit Scene (available on both iOS and visionOS)
    @Published var currentScene: RealityKit.Scene?
    
    // The local multi-peer session
    var multipeerSession: MultipeerSession?
    
    // The custom connectivity service (visionOS or iOS)
    var customService: MyCustomConnectivityService?
    
    // Session identification
    var sessionID: String = UUID().uuidString
    var sessionName: String = ""
    
    // Models collection
    var models: [Model] = []
    
    // Subscription storage
    private var subscriptions = Set<AnyCancellable>()
    
    // Multipeer state flags
    private var shouldStartMultipeerAfterModelsLoad: Bool = false
    
    // MARK: - Initialization
    override init() {
        super.init()
        print("ARViewModel initialized with sessionID: \(sessionID)")
    }
    
    deinit {
        stopMultipeerServices()
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
    }
    
    // MARK: - Model Loading
    
    /// Loads all available 3D models
    func loadModels() {
        guard models.isEmpty else { 
            print("Models already loaded, skipping loadModels()")
            return 
        }
        
        print("Starting to load models...")
        let modelTypes = ModelType.allCases()
        guard !modelTypes.isEmpty else {
            DispatchQueue.main.async {
                self.alertItem = AlertItem(
                    title: "No Models Found",
                    message: "No 3D model files were found. Please add .usdz files to the 'models' folder."
                )
                self.loadingProgress = 1.0 // Mark as complete even though there are no models
            }
            return
        }
        
        let totalModels = modelTypes.count
        var loadedModels = 0
        var failedModels = 0
        
        for mt in modelTypes {
            let model = Model(modelType: mt, arViewModel: self)
            models.append(model)
            
            Task {
                await model.loadModelEntity()
                
                await MainActor.run {
                    switch model.loadingState {
                    case .loaded:
                        loadedModels += 1
                        self.updateLoadingProgress(loaded: loadedModels, failed: failedModels, total: totalModels)
                        print("Loaded model: \(mt.rawValue) [\(loadedModels)/\(totalModels)]")
                    case .failed(let error):
                        failedModels += 1
                        self.updateLoadingProgress(loaded: loadedModels, failed: failedModels, total: totalModels)
                        print("Failed to load model: \(mt.rawValue) - \(error.localizedDescription)")
                        self.alertItem = AlertItem(
                            title: "Failed to Load Model",
                            message: "\(mt.rawValue.capitalized): \(error.localizedDescription)"
                        )
                    default:
                        break
                    }
                    
                    // Start multipeer if all models are processed and it was requested
                    let totalProcessed = loadedModels + failedModels
                    if totalProcessed >= totalModels && self.shouldStartMultipeerAfterModelsLoad {
                        self.startMultipeerServices()
                        self.shouldStartMultipeerAfterModelsLoad = false
                    }
                }
            }
        }
    }
    
    private func updateLoadingProgress(loaded: Int, failed: Int, total: Int) {
        let processed = loaded + failed
        self.loadingProgress = min(Float(processed) / Float(total), 1.0)
        
        if processed >= total {
            if failed > 0 {
                print("Loading complete. \(loaded) models loaded, \(failed) models failed.")
            } else {
                print("All \(loaded) models successfully loaded.")
            }
        }
    }
    
    // MARK: - Multipeer Connectivity
    
    /// Starts multipeer services immediately
    func startMultipeerServices() {
        guard multipeerSession == nil else {
            print("Multipeer session already active, skipping startMultipeerServices()")
            return
        }
        
        print("Starting multipeer services...")
        
        // Create multipeer session with proper metadata
        let metadataDict: [String: String] = [
            "sessionID": sessionID,
            "sessionName": sessionName.isEmpty ? "Default Session" : sessionName,
            "userRole": userRole.rawValue
        ]
        
        #if os(iOS)
        let peerID = MCPeerID(displayName: UIDevice.current.name)
        #else
        let peerID = MCPeerID(displayName: "visionOS Device")
        #endif
        
        let session = MultipeerSession(
            serviceType: "xr-anatomy",
            peerID: peerID,
            metadata: metadataDict,
            delegate: self
        )
        self.multipeerSession = session
        
        // Initialize custom connectivity service
        if let mpSession = multipeerSession {
            customService = MyCustomConnectivityService(
                multipeerSession: mpSession,
                arViewModel: self
            )
            
            #if os(iOS)
            // Attach to ARView scene if available
            if let arView = arView {
                do {
                    let syncService = try customService ?? RealityKit.MultipeerConnectivityService(session: mpSession.session)
                    arView.scene.synchronizationService = syncService
                    print("Attached synchronization service to ARView scene")
                } catch {
                    print("Error creating sync service: \(error)")
                }
            }
            #endif
        }
        
        print("Multipeer services started")
    }
    
    /// Stops all multipeer services
    func stopMultipeerServices() {
        print("Stopping multipeer services")
        multipeerSession?.session.disconnect()
        multipeerSession = nil
        customService = nil
        connectedPeers.removeAll()
        availableSessions.removeAll()
        print("Multipeer services stopped")
    }
    
    /// Defers multipeer service start until models are loaded
    func deferMultipeerServicesUntilModelsLoad() {
        print("Deferring multipeer services until models load")
        shouldStartMultipeerAfterModelsLoad = true
    }
    
    // MARK: - iOS-specific AR functionality
    #if os(iOS)
    /// Setup the ARView with necessary configuration
    func setupARView(_ arView: ARView) {
        self.arView = arView
        ARSessionManager.shared.configureSession(for: arView)
        arView.session.delegate = self
        
        // Add tap gesture recognizer for model placement
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        // Only start multipeer here if it wasn't deferred
        if !shouldStartMultipeerAfterModelsLoad && multipeerSession == nil {
            startMultipeerServices()
        }
    }
    
    /// Handle tap gestures for model placement
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        // Ensure user has permission to add models
        guard userRole != .viewer || isHostPermissionGranted else {
            alertItem = AlertItem(
                title: "Permission Denied",
                message: "You don't have permission to add models. Ask the host to grant you permission."
            )
            return
        }
        
        guard let arView = arView,
              let model = selectedModel,
              let modelEntity = model.modelEntity else {
            return
        }
        
        // Raycast to find placement position
        let tapLocation = sender.location(in: arView)
        let results = arView.raycast(from: tapLocation, allowing: .estimatedPlane, alignment: .any)
        
        guard let firstResult = results.first else {
            alertItem = AlertItem(
                title: "Placement Failed",
                message: "Couldn't find a surface. Try pointing at a flat surface."
            )
            return
        }
        
        // Create anchor for the model
        let anchorName = "\(model.modelType.rawValue)_\(UUID().uuidString)"
        let anchor = ARAnchor(name: anchorName, transform: firstResult.worldTransform)
        arView.session.add(anchor: anchor)
        placedAnchors.append(anchor)
        
        print("Placed model \(model.modelType.rawValue) at tap location")
    }
    
    /// Reset the AR session
    func resetARSession() {
        guard let arView = arView else { return }
        
        print("Resetting AR session")
        arView.session.pause()
        
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.isCollaborationEnabled = true
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        
        placedAnchors.removeAll()
        processedAnchorIDs.removeAll()
        
        print("AR session reset complete")
    }
    
    /// Clear all placed models
    func clearAllModels() {
        guard let arView = arView else { return }
        
        print("Clearing all models")
        for anchor in placedAnchors {
            arView.session.remove(anchor: anchor)
        }
        placedAnchors.removeAll()
        
        print("All models cleared")
    }
    
    /// Process an AR anchor and place the appropriate model
    func placeModel(for anchor: ARAnchor) {
        guard let arView = arView,
              let anchorName = anchor.name else { return }
        
        // Check if we've already processed this anchor
        if processedAnchorIDs.contains(anchor.identifier) {
            return
        }
        
        // Mark as processed to avoid duplicates
        processedAnchorIDs.insert(anchor.identifier)
        
        // Parse model name from anchor name
        let components = anchorName.components(separatedBy: "_")
        guard let modelName = components.first else { return }
        
        // Find corresponding model
        let matchingModels = models.filter { $0.modelType.rawValue.lowercased() == modelName.lowercased() }
        guard let model = matchingModels.first,
              let modelEntity = model.modelEntity?.clone(recursive: true) else {
            print("No matching model found for anchor: \(anchorName)")
            return
        }
        
        // Create anchor entity 
        let anchorEntity = AnchorEntity(anchor: anchor)
        anchorEntity.addChild(modelEntity)
        
        // Add to scene
        arView.scene.addAnchor(anchorEntity)
        print("Placed model \(modelName) for anchor: \(anchor.identifier)")
    }
    
    /// Send model transform to peers
    func sendTransform(for entity: Entity) {
        guard let customService = customService else { return }
        
        // Find the model for this entity
        var modelType: ModelType? = nil
        
        // Try to get model type from component first
        if let component = entity.components[ModelTypeComponent.self] {
            modelType = component.type
        }
        // Or search in our models dictionary
        else if let model = models.first(where: { $0.modelEntity === entity }) {
            modelType = model.modelType
        }
        
        if let modelType = modelType {
            customService.sendModelTransform(entity: entity, modelType: modelType)
        }
    }
    #endif
}

// MARK: - ARSessionDelegate (iOS only)
#if os(iOS)
extension ARViewModel: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if anchor.name != nil {
                placeModel(for: anchor)
            }
        }
    }
    
    func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
        guard let mpSession = multipeerSession,
              !mpSession.session.connectedPeers.isEmpty else { return }
        
        // Only send if it's a reliable chunk or we have few peers
        guard data.priority == .critical ||
              mpSession.session.connectedPeers.count < 3 else { return }
        
        do {
            let archivedData = try NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: true)
            mpSession.sendToAllPeers(archivedData, dataType: .collaborationData)
        } catch {
            print("Error archiving collaboration data: \(error)")
        }
    }
}
#endif

// MARK: - MultipeerSessionDelegate
extension ARViewModel: MultipeerSessionDelegate {
    func receivedData(_ data: Data, from peerID: MCPeerID) {
        print("ARViewModel: receivedData from \(peerID.displayName)")
        // Let the custom service handle the data parsing
        customService?.handleReceivedData(data, from: peerID)
    }
    
    func peerDidChangeState(peerID: MCPeerID, state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                    print("Peer \(peerID.displayName) connected. Total peers: \(self.connectedPeers.count)")
                }
            case .notConnected:
                if let idx = self.connectedPeers.firstIndex(of: peerID) {
                    self.connectedPeers.remove(at: idx)
                    print("Peer \(peerID.displayName) disconnected. Remaining peers: \(self.connectedPeers.count)")
                }
            default:
                print("Peer \(peerID.displayName) connection state changed to \(state)")
                break
            }
        }
    }
    
    func didReceiveInvitation(from peerID: MCPeerID,
                              invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            self.alertItem = AlertItem(
                title: "Invitation Received",
                message: "Would you like to join \(peerID.displayName)'s session?"
            )
            
            // Here we auto-accept for simplicity
            // In a real app, you might want to show a confirmation dialog
            invitationHandler(true, self.multipeerSession?.session)
        }
    }
    
    func foundPeer(peerID: MCPeerID, sessionID: String, sessionName: String) {
        DispatchQueue.main.async {
            let newSession = Session(sessionID: sessionID, sessionName: sessionName, peerID: peerID)
            
            // Only add if not already in the list
            if !self.availableSessions.contains(where: { $0.peerID == peerID }) {
                self.availableSessions.append(newSession)
                print("Found peer: \(peerID.displayName), sessionName=\(sessionName)")
            }
        }
    }
}
