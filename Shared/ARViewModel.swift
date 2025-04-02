import SwiftUI
import Combine
import MultipeerConnectivity
import RealityKit
import ARKit

/// Defines the synchronization modes for the AR experience.
enum SyncMode: String, Codable, CaseIterable {
    /// Synchronizes absolute world transforms. Relies on ARKit world alignment.
    case world = "World Space Sync"
    /// Synchronizes transforms relative to a detected physical image target.
    case imageTarget = "Image Target Sync"
}

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

    // Implement Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(sessionID)
        hasher.combine(peerID)
    }

    // Implement Equatable based on peerID for uniqueness in lists
    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.peerID == rhs.peerID
    }
}


/// Main view model for AR/XR functionality
class ARViewModel: NSObject, ObservableObject {

    // MARK: - Published properties
    @Published var selectedModel: Model? = nil // Keep this for iOS UI interaction
    @Published var alertItem: AlertItem?
    @Published var loadingProgress: Float = 0.0
    @Published var userRole: UserRole = .openSession
    @Published var isHostPermissionGranted = false // Used in iOS UI
    @Published var selectedSession: Session? = nil
    @Published var connectedPeers: [MCPeerID] = []
    @Published var availableSessions: [Session] = []

    // MARK: - Sync Mode Properties
    #if targetEnvironment(simulator)
    // Use world mode on simulator since image tracking doesn't work there
    @Published var currentSyncMode: SyncMode = .world
    #else
    // Use image target mode on real devices by default
    @Published var currentSyncMode: SyncMode = .imageTarget
    #endif
    // Shared anchor for image target mode (used by both platforms)
    let sharedAnchorEntity = AnchorEntity(.world(transform: matrix_identity_float4x4))
    @Published var isImageTracked: Bool = false // Track if the target image is currently tracked

    // RealityKit Scene (available on both iOS and visionOS)
    @Published var currentScene: RealityKit.Scene?

    // The local multi-peer session
    var multipeerSession: MultipeerSession?

    // The custom connectivity service (visionOS or iOS)
    var customService: MyCustomConnectivityService? // Initialized later

    // Session identification
    var sessionID: String = UUID().uuidString
    var sessionName: String = ""

    // Models collection (used by iOS UI, ModelManager handles internal model state)
    var models: [Model] = [] // Holds Model instances for UI selection etc.

    // Subscription storage
    private var subscriptions = Set<AnyCancellable>()

    // Multipeer state flags
    private var shouldStartMultipeerAfterModelsLoad: Bool = false

    // Reference to ModelManager (Now shared)
    // Use weak var if ModelManager might hold a strong ref back, otherwise strong is fine.
    @Published var modelManager: ModelManager? // Make it published if UI needs to react to its existence

    // MARK: - iOS ARKit references (Conditional)
    #if os(iOS)
    weak var arView: ARView?
    var arSessionManager = ARSessionManager.shared // Use the shared manager
    var arSessionDelegateHandler: ARSessionDelegateHandler? // Separate delegate handler
    var placedAnchors: [ARAnchor] = [] // Anchors placed by the user in iOS
    var processedAnchorIDs: Set<UUID> = [] // To avoid processing anchors multiple times

    // iOS Debug Toggles (can be moved to AppState if needed for visionOS too)
    @Published var isPlaneVisualizationEnabled: Bool = false
    @Published var areFeaturePointsEnabled: Bool = false
    @Published var isWorldOriginEnabled: Bool = false
    @Published var areAnchorOriginsEnabled: Bool = false
    @Published var isAnchorGeometryEnabled: Bool = false
    @Published var isSceneUnderstandingEnabled: Bool = false // Requires LiDAR
    #endif

    // MARK: - Initialization
    override init() {
        super.init()
        #if os(iOS)
        // Initialize the separate delegate handler for iOS
        self.arSessionDelegateHandler = ARSessionDelegateHandler(arViewModel: self)
        #endif
        print("ARViewModel initialized with sessionID: \(sessionID)")
    }

    deinit {
        stopMultipeerServices()
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        #if os(iOS)
        arView?.session.pause()
        #endif
    }

    // MARK: - Model Loading

    /// Loads all available 3D models sequentially on the main actor
    func loadModels() async {
        guard models.isEmpty else {
            print("Models already loaded, skipping loadModels()")
            return
        }

        print("Starting to load models...")
        let modelTypes = ModelType.allCases()
        guard !modelTypes.isEmpty else {
            self.alertItem = AlertItem(
                title: "No Models Found",
                message: "No 3D model files were found. Please add .usdz files to the 'models' folder."
            )
            self.loadingProgress = 1.0
            return
        }

        let totalModels = modelTypes.count
        var loadedModels = 0
        var failedModels = 0

        for mt in modelTypes {
            let model = await Model(modelType: mt, arViewModel: self)
            models.append(model)

            await model.loadModelEntity()

            switch await model.loadingState {
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

            if (loadedModels + failedModels) >= totalModels && self.shouldStartMultipeerAfterModelsLoad {
                self.startMultipeerServices()
                self.shouldStartMultipeerAfterModelsLoad = false
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

    /// Set the current scene for synchronization
    func setCurrentScene(_ scene: RealityKit.Scene) {
        currentScene = scene
        print("Set current scene for ARViewModel")
    }

    /// Start multipeer services with an optional model manager
    func startMultipeerServices(modelManager: ModelManager? = nil) {
        // Prevent starting if already running
        guard self.multipeerSession == nil else {
            print("Multipeer services already running.")
            // Ensure connectivity service has the correct model manager reference even if already running
            if let manager = modelManager ?? self.modelManager {
                 self.customService?.modelManager = manager
            }
            return
        }

        print("Attempting to start multipeer services...")
        // Create multipeer session
        let displayName = UIDevice.current.name
        // If sessionName is empty, use device name
        if self.sessionName.isEmpty {
            self.sessionName = displayName
        }
        self.multipeerSession = MultipeerSession(serviceName: "xr-anatomy", displayName: displayName)
        self.multipeerSession?.delegate = self
        print("Created multipeer session with name: \(displayName), advertising name: \(self.sessionName)")


        // Create connectivity service if it doesn't exist
        // Ensure modelManager is valid before creating service
        guard let manager = modelManager ?? self.modelManager else {
             print("Error: ModelManager is nil, cannot create CustomConnectivityService.")
             // Handle error appropriately, maybe show an alert
             return
        }

        if self.customService == nil {
             self.customService = MyCustomConnectivityService(
                 multipeerSession: self.multipeerSession!,
                 arViewModel: self,
                 modelManager: manager // Pass the non-optional modelManager
             )
             print("Created custom connectivity service with ModelManager")
        } else {
             // If service exists, ensure its modelManager reference is up-to-date (though it's strong now)
             self.customService?.modelManager = manager
        }

        // Start broadcasting
        self.multipeerSession?.startBrowsingAndAdvertising()
        print("Started browsing and advertising for peers")
    }

    /// Stop multipeer services
    func stopMultipeerServices() {
        guard self.multipeerSession != nil else {
            // print("Multipeer services already stopped.") // Optional: reduce log noise
            return
        }
        print("Stopping multipeer services...")
        self.multipeerSession?.stopBrowsingAndAdvertising()
        // Disconnect explicitly
        self.multipeerSession?.session.disconnect()
        self.multipeerSession = nil
        self.customService = nil // Assuming customService lifecycle is tied to multipeerSession
        // Clear connection states
        self.connectedPeers.removeAll()
        self.availableSessions.removeAll()
        self.selectedSession = nil
        print("Stopped and cleaned up multipeer services.")
    }

    /// Invite a peer to join the session
    func invitePeer(_ session: Session) {
        guard let multipeerSession = self.multipeerSession else {
            print("Cannot invite peer - no multipeer session available")
            return
        }

        print("Inviting peer: \(session.peerID.displayName)")
        multipeerSession.invitePeer(session.peerID)
        self.selectedSession = session
    }

    /// Defers multipeer service start until models are loaded
    func deferMultipeerServicesUntilModelsLoad() {
        print("Deferring multipeer services until models load")
        self.shouldStartMultipeerAfterModelsLoad = true
    }

    // MARK: - Test Messaging

    /// Sends a simple test message to all connected peers.
    func sendTestMessage() {
        guard let multipeerSession = self.multipeerSession, !multipeerSession.session.connectedPeers.isEmpty else {
            print("Cannot send test message: No connected peers.")
            return
        }

        let payload = TestMessagePayload(
            message: "Hello from \(UIDevice.current.name)!",
            senderName: multipeerSession.session.myPeerID.displayName
        )

        do {
            let data = try JSONEncoder().encode(payload)
            multipeerSession.sendToAllPeers(data, dataType: .testMessage) // Use DataType.testMessage
            print("Sent test message.")
        } catch {
            print("Error encoding TestMessagePayload: \(error)")
        }
    }

    // MARK: - iOS-specific AR functionality
    #if os(iOS)
    /// Setup the ARView with necessary configuration
    func setupARView(_ arView: ARView) {
        self.arView = arView
        self.setCurrentScene(arView.scene) // Set the scene

        // Configure the AR session using the shared manager
        self.arSessionManager.configureSession(for: arView)

        // Assign the custom delegate handler
        if let delegateHandler = self.arSessionDelegateHandler {
            arView.session.delegate = delegateHandler
        } else {
            print("Warning: ARSessionDelegateHandler not initialized.")
        }

        // Add tap gesture recognizer for model placement
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)

        // Only start multipeer here if it wasn't deferred
        if !self.shouldStartMultipeerAfterModelsLoad && self.multipeerSession == nil {
            self.startMultipeerServices()
        }
    }

    /// Handle tap gestures for model placement
    @MainActor @objc func handleTap(_ sender: UITapGestureRecognizer) {
        // Ensure user has permission to add models
        guard self.userRole != .viewer || self.isHostPermissionGranted else {
            self.alertItem = AlertItem(
                title: "Permission Denied",
                message: "You don't have permission to add models. Ask the host to grant you permission."
            )
            return
        }

        guard let arView = self.arView,
              let model = self.selectedModel,
              let modelEntity = model.modelEntity else {
            return
        }

        // Raycast to find placement position
        let tapLocation = sender.location(in: arView)
        // Use explicit types for raycasting parameters
        let results = arView.raycast(from: tapLocation, allowing: .estimatedPlane, alignment: .any)

        guard let firstResult = results.first else {
            self.alertItem = AlertItem(
                title: "Placement Failed",
                message: "Couldn't find a surface. Try pointing at a flat surface."
            )
            return
        }

        // Create anchor for the model
        let anchorName = "\(model.modelType.rawValue)_\(UUID().uuidString)"

        // Use a plain ARAnchor with just the transform
        let anchor = ARAnchor(transform: firstResult.worldTransform)

        // We'll store the modelType in our own data structures
        arView.session.add(anchor: anchor)
        self.placedAnchors.append(anchor)

        // Store the name mapping separately if needed
        let userInfo = ["modelName": model.modelType.rawValue, "anchorName": anchorName]
        NotificationCenter.default.post(name: Notification.Name("AnchorCreated"), object: anchor.identifier, userInfo: userInfo)

        print("Placed model \(model.modelType.rawValue) at tap location")
    }

    /// Reset the AR session
    @MainActor func resetARSession() {
        guard let arView = self.arView else { return }

        print("Resetting AR session")
        arView.session.pause() // Pause the session first

        // Clear existing anchors from the scene managed by RealityKit
        arView.scene.anchors.removeAll()

        // Clear internal tracking
        self.placedAnchors.removeAll()
        self.processedAnchorIDs.removeAll()
        self.modelManager?.reset() // Also reset models managed by ModelManager

        // Create new configuration
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .meshWithClassification
        }
        config.environmentTexturing = .automatic
        config.isCollaborationEnabled = true // Keep collaboration enabled

        // Run the session with the new configuration
        // Using resetTracking and removeExistingAnchors should clear ARKit's internal state
        // Use explicit type for options
        arView.session.run(config, options: [ARSession.RunOptions.resetTracking, ARSession.RunOptions.removeExistingAnchors])

        print("AR session reset complete")
    }

    /// Clear all placed models
    func clearAllModels() {
        guard let arView = self.arView else { return }

        print("Clearing all models")
        for anchor in self.placedAnchors {
            arView.session.remove(anchor: anchor)
        }
        self.placedAnchors.removeAll()

        print("All models cleared")
    }

    /// Process an AR anchor and place the appropriate model
    @MainActor func placeModel(for anchor: ARAnchor) {
        guard let arView = self.arView else { return }

        // Check if we've already processed this anchor
        if self.processedAnchorIDs.contains(anchor.identifier) {
            return
        }

        // Mark as processed to avoid duplicates
        self.processedAnchorIDs.insert(anchor.identifier)

        // Default to the first model type if we can't determine which one was intended
        // In a real app, you'd want a more robust way to track which anchor maps to which model
        let defaultModelType = self.models.first?.modelType

        // Try to find if this anchor has a model type associated with it through our notification system
        // Real apps would use a more robust approach like storing this mapping in a dictionary
        var modelName = defaultModelType?.rawValue

        // Simple approach: just place the selected model
        if let selectedModel = self.selectedModel {
            modelName = selectedModel.modelType.rawValue
        }

        // Find corresponding model
        guard let modelName = modelName else {
            print("No model selected to place for anchor: \(anchor.identifier)")
            return
        }

        let matchingModels = self.models.filter { $0.modelType.rawValue.lowercased() == modelName.lowercased() }
        guard let model = matchingModels.first,
              let modelEntity = model.modelEntity?.clone(recursive: true) else {
            print("No matching model found for anchor")
            return
        }

        // Create anchor entity positioned at the ARAnchor's world transform
        let anchorEntity = AnchorEntity(world: anchor.transform)
        anchorEntity.addChild(modelEntity)

        // Add to scene
        arView.scene.addAnchor(anchorEntity)
        print("Placed model \(modelName) for anchor: \(anchor.identifier)")
    }

    /// Broadcasts model transform using the unified sendTransform method.
    func broadcastModelTransform(entity: Entity, modelType: ModelType) {
        // This might be redundant if sendTransform is called directly from gestures/updates
        print("Broadcasting transform for \(modelType.rawValue)")
        sendTransform(for: entity)
    }
    #endif // End of os(iOS) specific block

    // MARK: - Transform Sending (Unified)

    /// Sends the transform of an entity to peers, respecting the current sync mode.
    /// This is the primary method to call for broadcasting transforms.
    func sendTransform(for entity: Entity) {
        guard let customService = self.customService, let modelManager = self.modelManager else {
            // print("Cannot send transform: Custom service or model manager not available.")
            return
        }

        // Find the associated Model object to get the ModelType
        let model = modelManager.modelDict[entity]
        let modelType = model?.modelType // May be nil if it's not a managed model entity

        // Determine if the transform should be relative to the image anchor
        let isRelativeToImageAnchor = (self.currentSyncMode == .imageTarget)

        // Send the transform using the connectivity service
        customService.sendModelTransform(
            entity: entity,
            modelType: modelType,
            relativeToImageAnchor: isRelativeToImageAnchor
        )
    }
} // End of ARViewModel class

// MARK: - ARSession Delegate
// ARSession delegate implementation moved to ARSessionDelegateHandler class

// MARK: - MultipeerSessionDelegate
extension ARViewModel: MultipeerSessionDelegate {
    func session(_ session: MultipeerSession, didReceiveData data: Data, from peerID: MCPeerID) {
        // Pass received data to the custom connectivity service
        customService?.handleReceivedData(data, from: peerID)
    }

    func session(_ session: MultipeerSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                print("Peer connected: \(peerID.displayName)")
            case .connecting:
                print("Peer connecting: \(peerID.displayName)")
            case .notConnected:
                if let index = self.connectedPeers.firstIndex(of: peerID) {
                    self.connectedPeers.remove(at: index)
                }
                // Also remove from available sessions if they disconnect before joining fully
                self.availableSessions.removeAll { $0.peerID == peerID }
                if self.selectedSession?.peerID == peerID {
                    self.selectedSession = nil // Clear selection if the selected peer disconnects
                }
                print("Peer disconnected: \(peerID.displayName)")
            @unknown default:
                print("Unknown peer state: \(peerID.displayName)")
            }
        }
    }

    func didReceiveInvitation(from peerID: MCPeerID, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations for simplicity
        invitationHandler(true, multipeerSession?.session)
        print("Accepted invitation from: \(peerID.displayName)")
    }

    func foundPeer(peerID: MCPeerID, sessionID: String, sessionName: String) {
        DispatchQueue.main.async {
            let newSession = Session(sessionID: sessionID, sessionName: sessionName, peerID: peerID)

            // Only add if not already in the list (check by peerID)
            if !self.availableSessions.contains(where: { $0.peerID == peerID }) {
                self.availableSessions.append(newSession)
                print("Found peer: \(peerID.displayName), sessionName=\(sessionName)")
            }
        }
    }
}
