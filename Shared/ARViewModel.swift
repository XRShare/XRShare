import SwiftUI
import Combine
import GroupActivities
import MultipeerConnectivity
import RealityKit
import ARKit

/// Defines the synchronization modes for the AR experience.
enum SyncMode: String, Codable, CaseIterable {
    /// Synchronizes absolute world transforms. Relies on ARKit world alignment.
    case world = "World Space Sync"
    /// Synchronizes transforms relative to a detected physical image target.
    case imageTarget = "Image Target Sync"
    /// Synchronizes transforms relative to a detected physical 3D object.
    case objectTarget = "Object Target Sync"
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
    // Default to image target mode for both device and simulator (simulator will fallback in configureARSession if needed)
    @Published var currentSyncMode: SyncMode = .imageTarget
    // Shared anchor for image/object target mode (used by both platforms)
    // Represents the coordinate system of the tracked physical target.
    let sharedAnchorEntity = AnchorEntity(.world(transform: matrix_identity_float4x4))
    @Published var isImageTracked: Bool = false // Track if the target image is *currently* detected/tracked
    @Published var isSyncedToImage: Bool = false // Track if the initial sync alignment via image has occurred
    @Published var isObjectTracked: Bool = false // Track if the target object is *currently* detected/tracked
    @Published var isSyncedToObject: Bool = false // Track if the initial sync alignment via object has occurred


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

            // Removed automatic start of multipeer services after model loading.
            // This should now only happen explicitly via StartupMenuView or MainMenu.

        } // End of loop
        
        // Ensure progress hits 1.0 if it hasn't already
        if loadingProgress < 1.0 {
             updateLoadingProgress(loaded: loadedModels, failed: failedModels, total: totalModels)
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

    // MARK: - Sync Control

    /// Resets the sync state, allowing detection to re-align the shared anchor (image or object target).
    @MainActor func triggerSync() {
        switch currentSyncMode {
        case .imageTarget:
            isSyncedToImage = false
            isImageTracked = false
            isSyncedToObject = false
            isObjectTracked = false
            print("Image sync triggered. Awaiting image target detection for re-alignment.")
            alertItem = AlertItem(
                title: "Image Sync",
                message: "Point your device towards the designated image target to re-align the session."
            )

        case .objectTarget:
            isSyncedToObject = false
            isObjectTracked = false
            isSyncedToImage = false
            isImageTracked = false
            print("Object sync triggered. Awaiting object target detection for re-alignment.")
            alertItem = AlertItem(
                title: "Object Sync",
                message: "Point your device towards the designated physical object to re-align the session."
            )

        default:
            print("Cannot trigger sync when not in Image or Object Target mode.")
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
        // Prepare discovery info
        let discoveryInfo = ["sessionID": self.sessionID, "sessionName": self.sessionName]
        
        self.multipeerSession = MultipeerSession(
            serviceName: "xr-anatomy",
            displayName: displayName,
            discoveryInfo: discoveryInfo // Pass discovery info here
        )
        self.multipeerSession?.delegate = self
        print("Created multipeer session with name: \(displayName), advertising name: \(self.sessionName), discoveryInfo: \(discoveryInfo)")


        // Create connectivity service if it doesn't exist
        // Ensure modelManager is valid before creating service
        guard let manager = modelManager ?? self.modelManager else {
             print("Error: ModelManager is nil, cannot create CustomConnectivityService.")
             // Handle error appropriately, maybe show an alert
             return
        }

        if self.customService == nil {
            guard let session = self.multipeerSession else {
                print("Error: multipeerSession is nil, cannot create CustomConnectivityService.")
                return
            }
            self.customService = MyCustomConnectivityService(
                multipeerSession: session,
                arViewModel: self,
                modelManager: manager
            )
            print("Created custom connectivity service with ModelManager")
        } else {
             // If service exists, ensure its modelManager reference is up-to-date (though it's strong now)
             self.customService?.modelManager = manager
        }

        // Start broadcasting
        self.multipeerSession?.startBrowsingAndAdvertising()
        print("Started browsing and advertising for peers")
        
        // --- SharePlay Integration ---
        // Start a SharePlay session using the sharedAnchorEntity as common origin anchor
        let originMatrix = sharedAnchorEntity.transformMatrix(relativeTo: nil).toArray()
        SharePlaySyncController.shared.startSession(with: originMatrix)
        // Handle initial origin transform from SharePlay to align shared anchor
        NotificationCenter.default.addObserver(forName: .sharePlayOriginTransform, object: nil, queue: .main) { [weak self] notif in
            // The notification object is the raw origin transform array ([Float])
            guard let originArray = notif.object as? [Float] else { return }
            // Update the shared anchor to the received origin transform
            let matrix = simd_float4x4.fromArray(originArray)
            self?.sharedAnchorEntity.transform.matrix = matrix
            print("SharePlay: updated sharedAnchorEntity with origin transform")
        }
        // Forward incoming SharePlay messages into the existing customService pipeline
        NotificationCenter.default.addObserver(forName: .sharePlayAddModel, object: nil, queue: .main) { [weak self] notif in
            guard let payload = notif.object as? AddModelPayload,
                  let data = try? JSONEncoder().encode(payload),
                  let svc = self?.customService else { return }
            var raw = Data([DataType.addModel.rawValue]); raw.append(data)
            svc.handleReceivedData(raw, from: svc.multipeerSession.session.myPeerID)
        }
        NotificationCenter.default.addObserver(forName: .sharePlayRemoveModel, object: nil, queue: .main) { [weak self] notif in
            guard let payload = notif.object as? RemoveModelPayload,
                  let data = try? JSONEncoder().encode(payload),
                  let svc = self?.customService else { return }
            var raw = Data([DataType.removeModel.rawValue]); raw.append(data)
            svc.handleReceivedData(raw, from: svc.multipeerSession.session.myPeerID)
        }
        NotificationCenter.default.addObserver(forName: .sharePlayModelTransform, object: nil, queue: .main) { [weak self] notif in
            guard let payload = notif.object as? ModelTransformPayload,
                  let data = try? JSONEncoder().encode(payload),
                  let svc = self?.customService else { return }
            var raw = Data([DataType.modelTransform.rawValue]); raw.append(data)
            svc.handleReceivedData(raw, from: svc.multipeerSession.session.myPeerID)
        }
        NotificationCenter.default.addObserver(forName: .sharePlayAnchorTransform, object: nil, queue: .main) { [weak self] notif in
            guard let payload = notif.object as? AnchorTransformPayload,
                  let data = try? JSONEncoder().encode(payload),
                  let svc = self?.customService else { return }
            var raw = Data([DataType.anchorWithTransform.rawValue]); raw.append(data)
            svc.handleReceivedData(raw, from: svc.multipeerSession.session.myPeerID)
        }
    }

    /// Stop multipeer services
    func stopMultipeerServices() {
        guard let sessionWrapper = self.multipeerSession else {
            return
        }
        print("Stopping multipeer services...")
        // Stop advertising/browsing then disconnect
        sessionWrapper.stopBrowsingAndAdvertising()
        sessionWrapper.session.disconnect()
        // Remove MCSession delegate to avoid any further incoming callbacks
        sessionWrapper.session.delegate = nil
        // Clear references
        self.multipeerSession = nil
        self.customService = nil
        // Clear connection states
        self.connectedPeers.removeAll()
        self.availableSessions.removeAll()
        self.selectedSession = nil
        self.isSyncedToImage = false // Reset sync status on disconnect
        self.isImageTracked = false
        self.isSyncedToObject = false
        self.isObjectTracked = false
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

    // Removed deferMultipeerServicesUntilModelsLoad() - No longer needed.

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
    @MainActor func setupARView(_ arView: ARView) {
        self.arView = arView
        self.setCurrentScene(arView.scene) // Set the scene
        // [L03] Ensure the shared anchor is added to the scene before any placements or sync
        arView.scene.addAnchor(sharedAnchorEntity)
        print("Added sharedAnchorEntity to ARView scene in setupARView.")

        // Initial session configuration based on the current sync mode
        reconfigureARSession() // Call reconfigure to handle initial setup

        // Assign the custom delegate handler
        if let delegateHandler = self.arSessionDelegateHandler {
            arView.session.delegate = delegateHandler
        } else {
            print("Warning: ARSessionDelegateHandler not initialized.")
        }

        // Add tap gesture recognizer for model placement and interaction
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)

        // Add manipulation gestures
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        arView.addGestureRecognizer(panGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        arView.addGestureRecognizer(pinchGesture)

        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        arView.addGestureRecognizer(rotationGesture)

        // Allow gestures to work simultaneously (optional, adjust as needed)
        // You might need to implement UIGestureRecognizerDelegate methods if more complex gesture interactions are required.
        // For now, let's assume default behavior is acceptable.

        // Removed automatic start of multipeer services from setupARView.
        // Multipeer is now started only via StartupMenuView actions.
    }

    /// Handle tap gestures for model placement OR selection/interaction (iOS)
    @MainActor @objc func handleTap(_ sender: UITapGestureRecognizer) {
        guard let arView = self.arView, let modelManager = self.modelManager, let customService = self.customService else {
            print("ARView, ModelManager, or CustomService not available for tap handling.")
            return
        }
        let tapLocation = sender.location(in: arView)

        // 1. Try to hit test existing entities first
        if let hitEntity = arView.entity(at: tapLocation), modelManager.modelDict[hitEntity] != nil {
            print("Tap hit existing model: \(hitEntity.name)")
            modelManager.handleTap(entity: hitEntity)
            // Ensure the tapped model is selected
            if let model = modelManager.modelDict[hitEntity] {
                modelManager.selectedModelID = model.modelType
            }
            return // Don't proceed to placement if we hit an existing model
        }

        // 2. If no entity hit, proceed with placement logic (if a model is selected in ModelManager)
        guard let selectedModelType = modelManager.selectedModelID,
              let modelToPlace = self.models.first(where: { $0.modelType == selectedModelType }) else {
            print("Tap missed entities and no model selected in ModelManager for placement.")
            // Optionally show an alert to select a model first
            // self.alertItem = AlertItem(title: "Select Model", message: "Please select a model from the menu before placing.")
            return
        }

        // Ensure user has permission to add models
        guard self.userRole != .viewer || self.isHostPermissionGranted else {
            self.alertItem = AlertItem(
                title: "Permission Denied",
                message: "You don't have permission to add models. Ask the host for permission."
            )
            return
        }

        // Raycast to find placement position on a plane
        let results = arView.raycast(from: tapLocation, allowing: .estimatedPlane, alignment: .any)
        guard let firstResult = results.first else {
            self.alertItem = AlertItem(
                title: "Placement Failed",
                message: "Couldn't find a surface. Try pointing at a flat surface."
            )
            return
        }

        // --- Direct Placement Logic ---
        Task {
            // Ensure the model is loaded
            if !modelToPlace.isLoaded() {
                await modelToPlace.loadModelEntity()
            }

            guard let modelEntity = modelToPlace.modelEntity?.clone(recursive: true) else {
                print("Failed to get or clone model entity for placement: \(modelToPlace.modelType.rawValue)")
                self.alertItem = AlertItem(title: "Placement Error", message: "Could not load the selected model.")
                return
            }

            // Assign a unique instance ID if it doesn't have one
            if modelEntity.components[InstanceIDComponent.self] == nil {
                modelEntity.components.set(InstanceIDComponent())
            }
            guard let idComp = modelEntity.components[InstanceIDComponent.self] else {
                print("Error: Missing InstanceIDComponent on modelEntity.")
                return
            }
            let instanceID = idComp.id

            // Determine the target parent and transform based on sync mode
            let targetParent: Entity
            let transformMatrix: simd_float4x4
            let isRelativeToSharedAnchor: Bool // Renamed for clarity

            if self.currentSyncMode == .imageTarget || self.currentSyncMode == .objectTarget {
                // --- Image or Object Target Mode ---
                targetParent = self.sharedAnchorEntity
                // Ensure shared anchor is in the scene
                if targetParent.scene == nil {
                    // Check if it exists in the scene anchors already but isn't linked (can happen)
                    if arView.scene.anchors
                        .first(where: { $0 == targetParent }) != nil {
                         print("SharedAnchorEntity found in scene anchors but scene property was nil. Using existing.")
                    } else {
                        if let anchorEntity = targetParent as? AnchorEntity {
                            arView.scene.addAnchor(anchorEntity)
                            print("Added sharedAnchorEntity to scene during placement.")
                        } else {
                            print("Error: targetParent is not an AnchorEntity, cannot add to scene.")
                        }
                    }
                }
                // Calculate the model's desired world transform from the raycast
                let desiredWorldTransform = Transform(matrix: firstResult.worldTransform)
                // Calculate the transform relative to the shared anchor's world transform
                // relativeTransform = worldTransform * inverse(anchorWorldTransform)
                let anchorWorldTransform = targetParent.transformMatrix(relativeTo: nil)
                transformMatrix = desiredWorldTransform.matrix * anchorWorldTransform.inverse

                isRelativeToSharedAnchor = true
                print("Placing \(modelToPlace.modelType.rawValue) relative to Shared Anchor (\(self.currentSyncMode.rawValue)). Relative Matrix calculated.")
            } else {
                // Place relative to the world (add to scene root or a world anchor)
                // For simplicity on iOS, let's add directly to the scene using an AnchorEntity
                // The transformMatrix will be the world transform from the raycast
                let worldAnchor = AnchorEntity(world: firstResult.worldTransform)
                arView.scene.addAnchor(worldAnchor)
                targetParent = worldAnchor // Parent is the new world anchor
                transformMatrix = matrix_identity_float4x4 // Model's local transform relative to its anchor is identity
                isRelativeToSharedAnchor = false
                print("Placing \(modelToPlace.modelType.rawValue) relative to World Anchor at \(firstResult.worldTransform.position).")
            }

            // Add the cloned entity to the target parent
            targetParent.addChild(modelEntity)
            // Set the calculated transform
            modelEntity.transform.matrix = transformMatrix

            // Create a new Model instance for ModelManager tracking
            // Use the existing loaded model data but create a new instance for tracking this placement
            let placedModelInstance = Model(modelType: modelToPlace.modelType, arViewModel: self)
            placedModelInstance.modelEntity = modelEntity // Assign the placed entity
            placedModelInstance.loadingState = .loaded // Mark as loaded

            // Register with ModelManager and ConnectivityService
            modelManager.modelDict[modelEntity] = placedModelInstance
            modelManager.placedModels.append(placedModelInstance)
            customService.registerEntity(modelEntity, modelType: modelToPlace.modelType, ownedByLocalPeer: true)
            print("Registered placed model \(modelToPlace.modelType.rawValue) (InstanceID: \(instanceID)) with ModelManager and ConnectivityService.")

            // Broadcast the addition
            // If relative, send the calculated relative transform; otherwise, send the world transform.
            let broadcastTransform = isRelativeToSharedAnchor ? transformMatrix : firstResult.worldTransform
            let payload = AddModelPayload(
                instanceID: instanceID, // Use the instance ID
                modelType: modelToPlace.modelType.rawValue,
                transform: broadcastTransform.toArray(),
                isRelativeToSharedAnchor: isRelativeToSharedAnchor // Use the generic flag name
            )
            do {
                let data = try JSONEncoder().encode(payload)
                self.multipeerSession?.sendToAllPeers(data, dataType: .addModel)
                print("Broadcasted addModel: \(modelToPlace.modelType.rawValue) (ID: \(instanceID)), Relative: \(isRelativeToSharedAnchor)")
            } catch {
                print("Error encoding AddModelPayload for placement: \(error)")
            }

            // Optional: Deselect model after placing
            // modelManager.selectedModelID = nil
            self.alertItem = AlertItem(title: "Model Placed", message: "\(modelToPlace.modelType.rawValue) placed successfully.")
        }
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
        self.isSyncedToImage = false // Reset sync status
        self.isImageTracked = false
        self.isSyncedToObject = false
        self.isObjectTracked = false

        // Create new configuration
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .meshWithClassification
        }
        config.environmentTexturing = .automatic
        config.isCollaborationEnabled = true // Keep collaboration enabled

        // Enable Occlusion frame semantics during reset as well
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
            config.frameSemantics.insert(.personSegmentationWithDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
             config.frameSemantics.insert(.sceneDepth)
        }

        // Run the session with the new configuration
        // Using resetTracking and removeExistingAnchors should clear ARKit's internal state
        // Use explicit type for options
        arView.session.run(config, options: [ARSession.RunOptions.resetTracking, ARSession.RunOptions.removeExistingAnchors])

        print("AR session reset complete with occlusion semantics.")
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

    /// Reconfigures the ARKit session based on the current `currentSyncMode`, optionally restoring from a world map. (iOS specific)
    @MainActor func reconfigureARSession(initialWorldMap: ARWorldMap? = nil) {
        guard let arView = self.arView else {
            print("[iOS] Cannot reconfigure ARSession: ARView not available.")
            return
        }
        print("[iOS] Reconfiguring ARSession for mode: \(currentSyncMode.rawValue)")

        var referenceImages = Set<ARReferenceImage>()
        if currentSyncMode == .imageTarget {
            // Load reference images from the asset catalog
            // Ensure the group name matches your Assets.xcassets
            guard let loadedImages = ARReferenceImage.referenceImages(inGroupNamed: "SharedAnchors", bundle: nil) else {
                print("[iOS] Error: Failed to load reference images from group 'SharedAnchors'. Switching to World Sync.")
                self.alertItem = AlertItem(title: "Error", message: "Could not load Image Target resources. Switching to World Sync.")
                // Fallback to world mode
                currentSyncMode = .world
            // Call reconfigure again with the updated mode and potentially the map if it was passed in
            reconfigureARSession(initialWorldMap: initialWorldMap)
                return
            }
            referenceImages = loadedImages
            print("[iOS] Loaded \(referenceImages.count) reference images for Image Target mode.")
            // Reset sync state when switching TO image target mode
            self.isSyncedToImage = false
            self.isImageTracked = false
        } else if currentSyncMode == .objectTarget {
             // Reset sync state when switching TO object target mode
             self.isSyncedToImage = false
             self.isImageTracked = false
             self.isSyncedToObject = false // Also reset object state
             self.isObjectTracked = false
        } else {
             // Reset sync state when switching FROM image/object target mode to world mode
             self.isSyncedToImage = false
             self.isImageTracked = false
             self.isSyncedToObject = false
             self.isObjectTracked = false
        }

        var referenceObjects = Set<ARReferenceObject>()
        if currentSyncMode == .objectTarget {
            var loadedObject: ARReferenceObject?
            var loadedURL: URL?
            
            // Add diagnostic logging to check bundle contents
            print("[iOS] Diagnosing reference object issue:")
            let resourceURLs = Bundle.main.urls(forResourcesWithExtension: "referenceobject", subdirectory: nil) ?? []
            print("[iOS] Found \(resourceURLs.count) .referenceobject files in bundle: \(resourceURLs.map { $0.lastPathComponent })")
            
            // Try different approaches to locate the reference object
            
            // Approach 1: Models subdirectory using url(forResource:)
            if let objectURL = Bundle.main.url(forResource: "model-mobile", withExtension: "referenceobject", subdirectory: "models") {
                print("[iOS] Found reference object at: \(objectURL)")
                do {
                    loadedObject = try ARReferenceObject(archiveURL: objectURL)
                    loadedURL = objectURL
                    print("[iOS] Successfully loaded reference object from models subdirectory.")
                } catch {
                    print("[iOS] Info: Failed to load reference object from models subdirectory: \(error.localizedDescription). Trying main bundle.")
                    loadedObject = nil // Ensure it's nil if loading failed
                }
            } else {
                print("[iOS] Reference object not found in models subdirectory")
            }

            // Approach 2: Main bundle using url(forResource:)
            if loadedObject == nil, let objectURL = Bundle.main.url(forResource: "model-mobile", withExtension: "referenceobject") {
                print("[iOS] Found reference object in main bundle at: \(objectURL)")
                do {
                    loadedObject = try ARReferenceObject(archiveURL: objectURL)
                    loadedURL = objectURL
                    print("[iOS] Successfully loaded reference object from main bundle.")
                } catch {
                    print("[iOS] Error: Failed to load reference object from main bundle: \(error.localizedDescription)")
                    loadedObject = nil // Ensure it's nil if loading failed
                }
            } else if loadedObject == nil {
                print("[iOS] Reference object not found in main bundle")
            }
            
            // Approach 3: Try using path(forResource:) which might handle spaces differently
            if loadedObject == nil, let objectPath = Bundle.main.path(forResource: "model-mobile", ofType: "referenceobject", inDirectory: "models") {
                let objectURL = URL(fileURLWithPath: objectPath)
                print("[iOS] Found reference object using path API at: \(objectURL)")
                do {
                    loadedObject = try ARReferenceObject(archiveURL: objectURL)
                    loadedURL = objectURL
                    print("[iOS] Successfully loaded reference object using path API.")
                } catch {
                    print("[iOS] Error: Failed to load reference object using path API: \(error.localizedDescription)")
                    loadedObject = nil
                }
            } else if loadedObject == nil {
                print("[iOS] Reference object not found using path API")
            }
            
            // Approach 4: Try searching for any reference object if the exact name fails
            if loadedObject == nil, let firstObjectURL = resourceURLs.first {
                print("[iOS] Attempting to load alternative reference object: \(firstObjectURL.lastPathComponent)")
                do {
                    loadedObject = try ARReferenceObject(archiveURL: firstObjectURL)
                    loadedURL = firstObjectURL
                    print("[iOS] Successfully loaded alternative reference object.")
                } catch {
                    print("[iOS] Error: Failed to load alternative reference object: \(error.localizedDescription)")
                    loadedObject = nil
                }
            }

            // Check if loading ultimately failed
            if let finalReferenceObject = loadedObject {
                referenceObjects.insert(finalReferenceObject)
                print("[iOS] Loaded reference object: \(finalReferenceObject.name ?? "Unnamed") from \(loadedURL?.path ?? "Unknown Path")")
                // Reset sync state when switching TO object target mode
                self.isSyncedToObject = false
                self.isObjectTracked = false
                self.isSyncedToImage = false // Also reset image state
                self.isImageTracked = false
            } else {
                print("[iOS] Error: Failed to load reference object 'model-mobile.referenceobject' from any location. Switching to World Sync.")
                print("[iOS] Bundle path: \(Bundle.main.bundlePath)")
                self.alertItem = AlertItem(title: "Error", message: "Could not load Object Target resources. Switching to World Sync.")
                currentSyncMode = .world
                reconfigureARSession() // Reconfigure for world mode
                return // Exit early as we are reconfiguring
            }
        }


        // Configure the session using the manager, restoring world map if provided
        self.arSessionManager.configureSession(
            for: arView,
            syncMode: currentSyncMode,
            referenceImages: referenceImages,
            referenceObjects: referenceObjects,
            initialWorldMap: initialWorldMap // Pass the map here
        )
        // Note: The actual configuration including frameSemantics happens within ARSessionManager.configureSession
        // which is called by the line above. No extra code needed here for semantics.
    }

    // Removed placeModel(for:) as placement is now handled directly in handleTap

    /// Broadcasts model transform using the unified sendTransform method.
    func broadcastModelTransform(entity: Entity, modelType: ModelType) {
        // This might be redundant if sendTransform is called directly from gestures/updates
        print("Broadcasting transform for \(modelType.rawValue)")
        sendTransform(for: entity)
    }

    // --- iOS Gesture Handling Methods ---

    // Store the entity being manipulated by gestures
    private var activeGestureEntity: Entity?
    private var initialRotation: simd_quatf?
    private var initialScale: SIMD3<Float>?

    @MainActor @objc func handlePan(_ sender: UIPanGestureRecognizer) {
        guard let arView = self.arView, let modelManager = self.modelManager else { return }
        let location = sender.location(in: arView)

        switch sender.state {
        case .began:
            if let entity = arView.entity(at: location), modelManager.modelDict[entity] != nil {
                activeGestureEntity = entity
                print("Pan began on \(entity.name)")
            } else {
                activeGestureEntity = nil
            }
        case .changed:
            guard let entity = activeGestureEntity else { return }
            
            // --- Improved Pan Translation using Raycasting ---
            // 1. Get the current 2D location of the gesture.
            let currentTapLocation = sender.location(in: arView)
            
            // 2. Perform a raycast from the current touch location.
            //    We aim for the horizontal plane the entity is on, or a plane at the entity's depth.
            //    Using existing planes is often more stable.
            let results = arView.raycast(from: currentTapLocation, allowing: .existingPlaneGeometry, alignment: .any)
            
            if let firstResult = results.first {
                // 3. Calculate the desired world position based on the raycast hit.
                let desiredWorldPosition = firstResult.worldTransform.position
                
                // 4. Calculate the delta needed to move the entity from its current position to the desired position.
                //    Get the entity's current world position.
                let currentWorldPosition = entity.position(relativeTo: nil)
                let translationDelta = desiredWorldPosition - currentWorldPosition
                
                // 5. Apply the delta using the ModelManager's handler (which might apply smoothing/clamping).
                //    Note: handleDragChange expects a *delta*, not an absolute position.
                modelManager.handleDragChange(entity: entity, translation: translationDelta, arViewModel: self)
                
            } else {
                // Fallback: If raycast fails (e.g., pointing off into space), maybe use the old approximate method or do nothing.
                print("Pan raycast failed, using approximate translation.")
                let translation = sender.translation(in: arView)
                let cameraTransform = arView.cameraTransform
                var worldTranslation = SIMD3<Float>(Float(translation.x), -Float(translation.y), 0) * 0.002 // Adjust sensitivity
                worldTranslation = cameraTransform.rotation.act(worldTranslation) // Rotate translation to world space
                modelManager.handleDragChange(entity: entity, translation: worldTranslation, arViewModel: self)
                sender.setTranslation(.zero, in: arView) // Reset translation only for fallback
            }
            // --- End Improved Pan ---
            
        case .ended, .cancelled:
             if let entity = activeGestureEntity {
                 modelManager.handleDragEnd(entity: entity, arViewModel: self)
                 print("Pan ended on \(entity.name)")
             }
             activeGestureEntity = nil
        default:
            break
        }
    }

    @MainActor @objc func handlePinch(_ sender: UIPinchGestureRecognizer) {
        guard let arView = self.arView, let modelManager = self.modelManager else { return }
        let location = sender.location(in: arView)

        switch sender.state {
        case .began:
             if let entity = arView.entity(at: location), modelManager.modelDict[entity] != nil {
                 activeGestureEntity = entity
                 initialScale = entity.scale
                 print("Pinch began on \(entity.name)")
             } else {
                 activeGestureEntity = nil
                 initialScale = nil
             }
             sender.scale = 1.0 // Reset scale factor
        case .changed:
            guard let entity = activeGestureEntity else { return }
            let scaleFactor = Float(sender.scale)
            modelManager.handleScaleChange(entity: entity, scaleFactor: scaleFactor, arViewModel: self)
            // Don't reset sender.scale here, let it accumulate relative to the start
        case .ended, .cancelled:
            if let entity = activeGestureEntity {
                 modelManager.handleScaleEnd(entity: entity, arViewModel: self)
                 print("Pinch ended on \(entity.name)")
            }
            activeGestureEntity = nil
            initialScale = nil
        default:
            break
        }
    }

    @MainActor @objc func handleRotation(_ sender: UIRotationGestureRecognizer) {
         guard let arView = self.arView, let modelManager = self.modelManager else { return }
         let location = sender.location(in: arView)

         switch sender.state {
         case .began:
             if let entity = arView.entity(at: location), modelManager.modelDict[entity] != nil {
                 activeGestureEntity = entity
                 initialRotation = entity.orientation(relativeTo: nil) // Store initial world rotation
                 print("Rotation began on \(entity.name)")
             } else {
                 activeGestureEntity = nil
                 initialRotation = nil
             }
             sender.rotation = 0 // Reset rotation
         case .changed:
             guard let entity = activeGestureEntity, let _ = self.initialRotation else { return }
             let angle = Float(sender.rotation) // Rotation angle in radians
             // Create rotation quaternion around the Y-axis (typical for 2D rotation gesture)
             let deltaRotation = simd_quatf(angle: -angle, axis: SIMD3<Float>(0, 1, 0)) // Negative angle might feel more natural

             // Apply rotation in world space
             // entity.setOrientation(initialRotation * deltaRotation, relativeTo: nil)
             // Or apply relative rotation (might be more intuitive)
             modelManager.handleRotationChange(entity: entity, rotation: deltaRotation, arViewModel: self)

             // Don't reset sender.rotation here, let it accumulate relative to start
         case .ended, .cancelled:
             if let entity = activeGestureEntity {
                 modelManager.handleRotationEnd(entity: entity, arViewModel: self)
                 print("Rotation ended on \(entity.name)")
             }
             activeGestureEntity = nil
             initialRotation = nil
         default:
             break
         }
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

        // Determine if the transform should be relative to the shared anchor (image or object)
        let isRelativeToSharedAnchor = (self.currentSyncMode == .imageTarget || self.currentSyncMode == .objectTarget)

        // Send the transform using the connectivity service
        // The sendModelTransform method in the service will calculate the correct relative/world transform based on the flag.
        customService.sendModelTransform(
            entity: entity,
            modelType: modelType,
            relativeToSharedAnchor: isRelativeToSharedAnchor // Pass the flag indicating intent
        )
    }
    
    #if os(iOS)
    /// Sends the current ARWorldMap to a newly connected peer for session alignment.
    /// Only the host should call this, to restore world tracking on late joiners.
    func sendWorldMap(to peerID: MCPeerID) {
        guard self.userRole == .host else {
            print("Only the host can send the world map.")
            return
        }
        guard let arView = self.arView, let multipeer = self.multipeerSession else {
            print("Cannot send world map: ARView or multipeer session not available.")
            return
        }
        print("Attempting to get current ARWorldMap to send to \(peerID.displayName)...")
        arView.session.getCurrentWorldMap { worldMap, error in
            guard let map = worldMap else {
                print("Failed to get current ARWorldMap")
                // Optionally, inform the new peer that map sharing failed
                return
            }

            do {
                // Archive the map
                let data = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                // Send the map data to the specific peer
                // Ensure DataType.arWorldMap exists and is used
                multipeer.sendToPeer(data, peerID: peerID, dataType: .arWorldMap)
                print("Successfully sent ARWorldMap (\(data.count) bytes) to \(peerID.displayName)")
            } catch {
                print("Error archiving ARWorldMap: \(error)")
            }
        }
    }
    #endif
    
    // MARK: - Synchronization on Connect
    
    /// Synchronizes locally owned models to a newly connected peer
    /// Called when a new peer connects to the session
    private func syncLocalModels(to targetPeerID: MCPeerID) {
        print("Synchronizing locally owned models to newly connected peer: \(targetPeerID.displayName)")

        guard let multipeerSession = self.multipeerSession,
              let customService = self.customService,
              let modelManager = self.modelManager else {
            print("Cannot sync models: Required services not initialized")
            return
        }

        // Get locally owned entities from the connectivity service
        let locallyOwnedEntities = customService.locallyOwnedEntities

        // If we don't have any models to sync, just log and return
        if locallyOwnedEntities.isEmpty {
            print("No locally owned models to sync with new peer")
            return
        }

        print("Found \(locallyOwnedEntities.count) locally owned models to sync")

        // For each locally owned entity, create and send an AddModelPayload
        for entityID in locallyOwnedEntities {
            // Look up the entity using the entityLookup dictionary
            guard let entity = customService.entityLookup[entityID],
                  let model = modelManager.modelDict[entity],
                  let instanceIDComponent = entity.components[InstanceIDComponent.self] else { // Get the component
                print("Failed to get entity, model data, or InstanceIDComponent for entity ID: \(entityID)")
                continue
            }
            let instanceID = instanceIDComponent.id // Get the ID from the component

            // Determine and compute the transform based on sync mode
            var isRelative = false
            let transform: simd_float4x4
            if self.currentSyncMode == .imageTarget || self.currentSyncMode == .objectTarget {
                // Attempt relative transform only if shared anchor is in the scene
                if self.sharedAnchorEntity.scene != nil {
                    transform = entity.transformMatrix(relativeTo: self.sharedAnchorEntity)
                    isRelative = true
                    print("Syncing \(model.modelType.rawValue) (ID: \(instanceID)) relative to shared anchor.")
                } else {
                    // Fallback to world transform if anchor not ready
                    transform = entity.transformMatrix(relativeTo: nil)
                    isRelative = false
                    print("Warning: Shared anchor not ready. Syncing \(model.modelType.rawValue) (ID: \(instanceID)) with world transform.")
                }
            } else {
                // World sync mode
                transform = entity.transformMatrix(relativeTo: nil)
                isRelative = false
                print("Syncing \(model.modelType.rawValue) (ID: \(instanceID)) with world transform.")
            }

            // Create AddModelPayload using instanceID
            let payload = AddModelPayload(
                instanceID: instanceID, // Use the correct instance ID
                modelType: model.modelType.rawValue,
                transform: transform.toArray(),
                isRelativeToSharedAnchor: isRelative // Send the correct relative flag
            )

            do {
                let data = try JSONEncoder().encode(payload)
                // Send only to the specific new peer, not to all peers
                multipeerSession.sendToPeer(data, peerID: targetPeerID, dataType: .addModel)
                print("Sent model sync: \(model.modelType.rawValue) (ID: \(instanceID)) to \(targetPeerID.displayName), Relative: \(isRelative)")
            } catch {
                print("Error encoding AddModelPayload for sync: \(error)")
            }
        }
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
                // Host should send world map first to align coordinate spaces
                #if os(iOS)
                // Check if current user is host before sending map
                if self.userRole == .host {
                    print("Acting as host, sending world map to new peer \(peerID.displayName)")
                    self.sendWorldMap(to: peerID)
                } else {
                    print("Acting as client, waiting for world map from host.")
                }
                #endif
                // Then sync locally owned models to the newly connected peer
                // Delay slightly to allow map processing? Or handle order via flags?
                // For now, send immediately after map send attempt.
                self.syncLocalModels(to: peerID)
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