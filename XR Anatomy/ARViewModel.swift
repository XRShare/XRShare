// Kind of the main file. There's a lot going on in here...

import SwiftUI
import RealityKit
import ARKit
import Combine
import MultipeerConnectivity

enum UserRole {
    case host
    case viewer
    case openSession  // for pure collaboration sessions (disabled atm)
}

class ARViewModel: NSObject, ObservableObject {
    // MARK: Published Properties
    @Published var selectedModel: Model? = nil 
    @Published var alertItem: AlertItem?
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isPlaneVisualizationEnabled: Bool = false
    @Published var loadingProgress: Float = 0.0  // Track loading progress
    @Published var userRole: UserRole = .openSession
    @Published var isHostPermissionGranted: Bool = false
    
    // Debug feature toggle properties with didSet observers
    @Published var areFeaturePointsEnabled = false { didSet { updateDebugOptions() }}
    @Published var isWorldOriginEnabled = false { didSet { updateDebugOptions() }}
    @Published var areAnchorOriginsEnabled = false { didSet { updateDebugOptions() }}
    @Published var isAnchorGeometryEnabled = false { didSet { updateDebugOptions() }}
    @Published var isSceneUnderstandingEnabled = false { didSet { updateDebugOptions() }}

    // Used for session management
    @Published var availableSessions: [(peerID: MCPeerID, sessionID: String, sessionName: String)] = []
    @Published var selectedSession: (peerID: MCPeerID, sessionID: String, sessionName: String)?
    
    
    // MARK: Properties
    var arView: ARView? {
        didSet {
            if arView != nil && deferredStartMultipeerServices {
                startMultipeerServices()
                deferredStartMultipeerServices = false
            }
        }
    }
    var models: [Model] = []
    var placedAnchors: [ARAnchor] = []
    var anchorEntities: [UUID: AnchorEntity] = [:]
    var pendingAnchorPayloads: [UUID: AnchorTransformPayload] = [:]
    var processedAnchorIDs: Set<UUID> = []
    var anchorsAddedLocally: Set<UUID> = []
    var pendingAnchors: [UUID: ARAnchor] = [:]
    
    var multipeerSession: MultipeerSession!
    var pendingPeerToConnect: MCPeerID? // was private...
    var sessionName: String = ""
    var sessionID: String = UUID().uuidString {
        didSet {
            print("Session ID set to: \(sessionID)")
        }
    }
    private var receivedWorldMap: ARWorldMap?  // Store received world map
    private let minimumFeaturePointThreshold = 100  // Threshold for feature points
    private var subscriptions = Set<AnyCancellable>()
    private var deferredStartMultipeerServices = false
    private var shouldStartMultipeerSession = false // Defer multipeer services
    
    // Gesture tracking properties
    private var activeEntity: ModelEntity?
    private var initialScale: SIMD3<Float> = SIMD3<Float>(repeating: 1.0)
    private var initialRotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
    private var initialTouchWorldPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    private var initialEntityWorldPosition: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    private var touchToEntityOffset: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    
    // For moving the model with pan gesture
    private var initialPanLocation: CGPoint?
    private var initialModelPosition: SIMD3<Float>?
    
    
    


    // MARK: - Initializer
    override init() {
        super.init()
        // loadModels() <-- is now called by ContentView.swift
    }

    // MARK: Load Models
    func loadModels() {
        guard models.isEmpty else { return }

        let modelTypes = ModelType.allCases()
        let totalModels = modelTypes.count
        var loadedModels = 0

        for modelType in modelTypes {
            let model = Model(modelType: modelType)
            models.append(model)

            model.$loadingState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self else { return }
                    switch state {
                    case .loaded:
                        loadedModels += 1
                        self.loadingProgress = Float(loadedModels) / Float(totalModels)

                        if loadedModels == totalModels {
                            print("All models loaded successfully.")
                            self.enableMultipeerServicesIfDeferred()
                            // Now safe to process received anchors
                            // self.processPendingAnchors()  <-- used to do this here, now is called from in ContentView
                        }
                    case .failed(let error):
                        self.alertItem = AlertItem(
                            title: "Failed to Load Model",
                            message: "Model \(modelType.rawValue.capitalized): \(error.localizedDescription)"
                        )
                    default: break
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

        // Set up AR session configuration
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        // Will crash if not supported, but helps iPhone 12+ devices (with LiDAR) read the scene
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .meshWithClassification  // Enable scene reconstruction
        }
        config.environmentTexturing = .automatic // Helps detect the environment
        config.isCollaborationEnabled = true // Enable collaboration
        arView.session.run(config) // Run AR session
        // Reapply scene understanding options
        arView.environment.sceneUnderstanding.options = .default
        // Print the options to confirm
        printSceneUnderstandingOptions(for: arView)

        // Add Gesture Recognizers
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))

        arView.addGestureRecognizer(tapGesture)
        arView.addGestureRecognizer(panGesture)
        arView.addGestureRecognizer(pinchGesture)
        arView.addGestureRecognizer(rotationGesture)

        // Start MultipeerSession if it was deferred
        if shouldStartMultipeerSession {
            print("arView is now initialized. Starting deferred MultipeerSession.")
            startMultipeerServices()
        }
    }

    func printSceneUnderstandingOptions(for arView: ARView) {
        let options = arView.environment.sceneUnderstanding.options

        print("\n\nScene Understanding Options:")

        if options.contains(.physics) {
            print("- Physics enabled")
        }
        if options.contains(.receivesLighting) {
            print("- Receives lighting enabled")
        }
        if options.contains(.occlusion) {
            print("- Occlusion enabled")
        }
        if options.contains(.collision) {
            print("- Collision enabled")
        }

        if options.isEmpty {
            print("- No scene understanding options are enabled")
        }
        print("\n\n")
    }
    
    // MARK: Multipeer Control
    func startMultipeerServices() {
        guard multipeerSession == nil else {
            print("MultipeerSession is already initialized.")
            return
        }

        // For hosts and open sessions, ensure arView is initialized
        if userRole == .host || userRole == .openSession {
            guard arView != nil else {
                print("arView is not initialized yet. Deferring MultipeerSession start.")
                deferredStartMultipeerServices = true
                return
            }
        }

        print("Starting MultipeerSession with role: \(userRole)")
        multipeerSession = MultipeerSession(sessionID: sessionID, sessionName: sessionName, userRole: userRole)
        multipeerSession?.delegate = self
        print("Multipeer services initialized with session ID \(sessionID ?? "Unknown").")
        multipeerSession?.start()
        print("Multipeer services started.")

        // If we have a pending peer to connect to, invite them
        if let peerID = pendingPeerToConnect {
            multipeerSession?.invitePeer(peerID, sessionID: sessionID ?? "Unknown")
            pendingPeerToConnect = nil
        }
    }
    
    func connectToSession(peerID: MCPeerID) {
        if let multipeerSession = multipeerSession {
            multipeerSession.invitePeer(peerID, sessionID: sessionID ?? "Unknown")
        } else {
            print("MultipeerSession is not initialized yet. Storing pending peer.")
            pendingPeerToConnect = peerID
        }
    }
    
    func deferMultipeerServicesUntilModelsLoad() {
        shouldStartMultipeerSession = true
    }

    func enableMultipeerServicesIfDeferred() {
        if shouldStartMultipeerSession {
            startMultipeerServices()
        }
    }

    func invitePeer(_ peerID: MCPeerID, sessionID: String) {
        multipeerSession.invitePeer(peerID, sessionID: sessionID)
    }
    
    func toggleHostPermissions() {
        isHostPermissionGranted.toggle()
        sendPermissionUpdateToPeers(isGranted: isHostPermissionGranted)
        print("Host permission toggled: \(isHostPermissionGranted)")
        if isHostPermissionGranted {
            syncSceneData() // Synchronize the scene after granting permissions
        }
    }

    func sendPermissionUpdateToPeers(isGranted: Bool) {
        do {
            let data = try JSONEncoder().encode(isGranted)
            multipeerSession?.sendToAllPeers(data, dataType: .permissionUpdate)
            print("Sent permission update to peers: \(isGranted)")
        } catch {
            print("Failed to encode permission update: \(error.localizedDescription)")
        }
    }



    // MARK: GESTURE handling  ---------------------------------------------------------------------
    // Tap Gesture
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        guard userRole != .viewer || isHostPermissionGranted else { return } // Disable for viewers

        let location = sender.location(in: arView)
        guard let arView = arView else {
            print("arView could not be unwrapped for some reason - top of @objc func handleTap()")
            return
        }
        let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)

        if let result = results.first, let model = selectedModel, let modelEntity = model.modelEntity {
            // Generate a unique identifier for this model instance
            let uniqueID = UUID().uuidString
            // Set the anchor name to include both the model type and the unique ID
            let anchorName = "\(model.modelType.rawValue)_\(uniqueID)"
            let anchor = ARAnchor(name: anchorName, transform: result.worldTransform)
            arView.session.add(anchor: anchor)

            // Add to placedAnchors
            placedAnchors.append(anchor)

            // **Add to anchorsAddedLocally**
            anchorsAddedLocally.insert(anchor.identifier)

            // Propagate the new anchor
            sendAnchorWithTransform(anchor: anchor)
        }
        printSceneUnderstandingOptions(for: arView)
    }

    // Pan Gesture with "Advanced Functionality"
    @objc func handlePan(_ sender: UIPanGestureRecognizer) {
        guard userRole != .viewer || isHostPermissionGranted else { return } // Disable for viewers
        guard let arView = arView else {
            print("arView could not be unwrapped for some reason - top of @objc func handlePan()")
            return
        }

        let location = sender.location(in: arView)

        if sender.state == .began {
            activeEntity = findClosestModelEntity(to: location)
            if let entity = activeEntity {
                // Perform a raycast to find the world position under the finger
                if let raycastResult = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any).first {
                    initialTouchWorldPosition = raycastResult.worldTransform.translation
                    initialEntityWorldPosition = entity.transform.translation
                    // Calculate the offset between the entity's position and the touch position
                    touchToEntityOffset = initialEntityWorldPosition - initialTouchWorldPosition
                }
            }
        }

        guard let entity = activeEntity else { return }

        if sender.state == .changed {
            // Perform a raycast from the current finger location
            if let raycastResult = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any).first {
                let currentTouchWorldPosition = raycastResult.worldTransform.translation
                // Update the entity's position to maintain the offset from the touch position
                let newEntityWorldPosition = currentTouchWorldPosition + touchToEntityOffset

                var newTransform = entity.transform
                newTransform.translation = newEntityWorldPosition
                entity.transform = newTransform
            }
        }

        if sender.state == .ended {
            sendModelTransform(entity)
            activeEntity = nil
        }
    }

    // Pinch Gesture (Scale)
    @objc func handlePinch(_ sender: UIPinchGestureRecognizer) {
        guard userRole != .viewer || isHostPermissionGranted else { return } // Disable for viewers

        let location = sender.location(in: arView)

        if sender.state == .began {
            activeEntity = findClosestModelEntity(to: location)
            initialScale = activeEntity?.transform.scale ?? SIMD3<Float>(repeating: 1.0)
        }

        guard let entity = activeEntity else { return }

        if sender.state == .changed {
            let scaleFactor = Float(sender.scale)
            entity.transform.scale = initialScale * SIMD3<Float>(repeating: scaleFactor)
        }

        if sender.state == .ended {
            sender.scale = 1.0
            sendModelTransform(entity)
            activeEntity = nil
        }
    }

    // Rotation Gesture
    @objc func handleRotation(_ sender: UIRotationGestureRecognizer) {
        guard userRole != .viewer || isHostPermissionGranted else { return } // Disable for viewers

        let location = sender.location(in: arView)

        if sender.state == .began {
            activeEntity = findClosestModelEntity(to: location)
            // Determine the rotation axis based on the model's type
            if let modelType = selectedModel?.modelType, modelType.shouldRotateAroundZAxis {
                initialRotation = activeEntity?.transform.rotation ?? simd_quatf(angle: 0, axis: SIMD3<Float>(0, 0, 1)) // Z-axis
            } else {
                initialRotation = activeEntity?.transform.rotation ?? simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)) // Y-axis
            }
        }

        guard let entity = activeEntity else { return }

        if sender.state == .changed {
            let rotationAngle = Float(sender.rotation) * -1.0 // x -1 inverts the direction, which feels more intuitive
            let rotationAxis = (selectedModel?.modelType.shouldRotateAroundZAxis ?? false) ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
            let rotationDelta = simd_quatf(angle: rotationAngle, axis: rotationAxis)
            entity.transform.rotation = initialRotation * rotationDelta
        }

        if sender.state == .ended {
            sender.rotation = 0.0
            sendModelTransform(entity)
            activeEntity = nil
        }
    }

    // (helper function) Find Closest Model Entity
    private func findClosestModelEntity(to location: CGPoint) -> ModelEntity? {
        guard let arView = arView else {
            print("arView could not be unwrapped for some reason - top of findClosestModelEntity() - returning null... ")
            return nil
        }
        return arView.entity(at: location) as? ModelEntity
    }
    // MARK: --- end of GESTURES ------------------------------------------------------------------

    
    func sendModelTransform(_ modelEntity: ModelEntity) {
        let modelID = modelEntity.name
        guard !modelID.isEmpty else {
            print("Model entity has no ID")
            return
        }

        // Get the model's transform matrix
        let transformMatrix = modelEntity.transform.matrix

        // Convert the matrix to an array of Floats
        let transformArray = transformMatrix.toArray()

        // Package the data
        do {
            // Encode the modelID and transform
            let payload = ModelTransformPayload(modelID: modelID, transform: transformArray)
            let data = try JSONEncoder().encode(payload)

            // Send the data
            multipeerSession?.sendToAllPeers(data, dataType: .modelTransform)
        } catch {
            print("Failed to encode model transform: \(error.localizedDescription)")
        }
    }

    // MARK: - Sync Scene Data
    func syncSceneData() {
        // No need to manually sync ARWorldMap or anchors (for now...)
        print("Sync initiated: Collaboration data will be shared automatically.")
    }

    // MARK: - Clear All Models
    func clearAllModels() {
        guard let arView = arView else {
            print("Couldn't unwrap arView in clearAllModels(), in ARViewModel.swift, for some reason...")
            return
        }
        let anchorIDs = placedAnchors.map { $0.identifier }
        for anchor in placedAnchors {
            arView.session.remove(anchor: anchor)
            if let anchorEntity = anchorEntities[anchor.identifier] {
                arView.scene.removeAnchor(anchorEntity)
                anchorEntities.removeValue(forKey: anchor.identifier)
            }
        }
        placedAnchors.removeAll()
        print("All models this user contributed have been cleared from the scene.")

        // Send the anchor IDs to peers to remove these anchors
        do {
            let ids = anchorIDs.map { $0.uuidString }
            let data = try JSONEncoder().encode(ids)
            multipeerSession?.sendToAllPeers(data, dataType: .removeAnchors)
        } catch {
            print("Failed to encode anchor IDs for removal: \(error.localizedDescription)")
        }
    }

    // MARK: - Place Model in Scene
    func placeModel(for anchor: ARAnchor, modelID: String? = nil, transformArray: [Float]? = nil) {
        print("Attempting to place model for anchor: \(anchor.name ?? "Unnamed")")
        
        guard let anchorName = anchor.name else {
            print("Anchor has no name")
            return
        }

        let modelID = modelID ?? {
            let components = anchorName.split(separator: "_", maxSplits: 1)
            return components.count == 2 ? String(components[1]) : UUID().uuidString
        }()
        
        let modelTypeName = String(anchorName.split(separator: "_").first ?? "")
        print("Extracted modelTypeName: \(modelTypeName)")
        print("Available models: \(models.map { $0.modelType.rawValue })")

        // Case-insensitive comparison
        guard let model = models.first(where: { $0.modelType.rawValue.lowercased() == modelTypeName.lowercased() }), let modelEntity = model.modelEntity else {
            print("Model not found for anchor with type \(modelTypeName)")
            return
        }

        let anchorEntity = AnchorEntity(anchor: anchor)
        let modelClone = modelEntity.clone(recursive: true)
        modelClone.name = modelID // Assign the unique ID to the model entity

        // Apply the transform if provided
        if let transformArray = transformArray {
            let transformMatrix = simd_float4x4.fromArray(transformArray)
            print("Applying transform matrix: \(transformMatrix)")
            modelClone.transform.matrix = transformMatrix
        } else {
            modelClone.scale *= SIMD3<Float>(repeating: 0.8) // Adjust model scale if necessary
        }

        // Add collision component to model entity for interaction
        modelClone.generateCollisionShapes(recursive: true)

        anchorEntity.addChild(modelClone)
        
        guard let arView = arView else {
            print("Couldn't unwrap arView in placeModel()")
            return
        }
        
        arView.scene.addAnchor(anchorEntity)
        print("Model added to scene with unique ID \(modelID)")
        
        // Log model's world position
        let modelWorldPosition = modelClone.position(relativeTo: nil)
        print("Model \(modelID) world position: \(modelWorldPosition)")

        // Store the AnchorEntity
        anchorEntities[anchor.identifier] = anchorEntity
        // Mark the anchor as processed
        processedAnchorIDs.insert(anchor.identifier)
    }
    
    // Function to process any anchors that were received before models loaded
    func processPendingAnchors() {
        for (anchorID, payload) in pendingAnchorPayloads {
            if let anchor = arView?.session.currentFrame?.anchors.first(where: { $0.identifier == anchorID }) {
                // Proceed with placing the model
                placeModel(for: anchor, modelID: payload.modelID, transformArray: payload.transform)
                processedAnchorIDs.insert(anchor.identifier)
                print("Placed model for anchor \(anchor.identifier) with transform.")
            } else {
                print("Anchor not found for ID: \(anchorID)")
            }
        }
        pendingAnchorPayloads.removeAll()
    }

    func updateDebugOptions() {
        arView?.debugOptions = []

        if areFeaturePointsEnabled { arView?.debugOptions.insert(.showFeaturePoints) }
        if isWorldOriginEnabled { arView?.debugOptions.insert(.showWorldOrigin) }
        if areAnchorOriginsEnabled { arView?.debugOptions.insert(.showAnchorOrigins) }
        if isAnchorGeometryEnabled { arView?.debugOptions.insert(.showAnchorGeometry) }
        if isSceneUnderstandingEnabled { arView?.debugOptions.insert(.showSceneUnderstanding) }
    }

    // Function to toggle plane visualization
    func togglePlaneVisualization(isEnabled: Bool) {
        if isEnabled {
            // Enable visualization; add back any new planes as they're detected
            guard let arView = arView else {
                print("Couldn't unwrap arView in togglePlaneVisualization()")
                return
            }
            arView.session.run(arView.session.configuration!, options: [.removeExistingAnchors])
        } else {
            // Disable visualization; remove all plane entities from the scene
            removeAllPlaneEntities()
        }
    }

    // Function to remove all plane entities
    func removeAllPlaneEntities() {
        guard let arView = arView else {
            print("Couldn't unwrap arView in removeAllPlaneEntities()")
            return
        }
        arView.scene.anchors.forEach { anchor in
            anchor.children.forEach { entity in
                if let planeEntity = entity as? ModelEntity, planeEntity.name == "plane" {
                    anchor.removeChild(planeEntity)
                }
            }
        }
    }
    
    func validateWorldMap(_ worldMap: ARWorldMap) -> Bool {
        let minimumAnchorCount = 5
        let minimumFeaturePointCount = 100

        // Directly access rawFeaturePoints since it's non-optional
        let featurePointCount = worldMap.rawFeaturePoints.points.count
        return worldMap.anchors.count >= minimumAnchorCount && featurePointCount >= minimumFeaturePointCount
    }
    
    func stopMultipeerServices() {
        multipeerSession?.disconnect()
        multipeerSession?.delegate = nil
        multipeerSession = nil
        print("Multipeer services stopped.")
    }
    
    func resetARSession() {
    // used when user backs out of a session to the main menu
        guard let arView = arView else {
            print("ARView is not initialized`.")
            return
        }
        // Cancel subscriptions
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        
        // Clear other delegates or observers
        multipeerSession?.delegate = nil
        NotificationCenter.default.removeObserver(self)
        print("ARViewModel deinitialized and cleaned up.")
        
        // Remove ARSession delegate
        arView.session.delegate = nil
        
        // Pause and reset the session
        arView.session.pause()
        arView.scene.anchors.removeAll()
        if let configuration = arView.session.configuration {
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            print("AR session reset.")
        } else {
            print("AR session configuration not found.")
        }
        
        // clear all variables
        reinitializeState()
        
        // Reassign the delegate
        arView.session.delegate = self
        
        // loadModels()  <-- you'd likely want to do this once inside the session, in the real world, and have the Join users DL the models from the Host (or each other, P2P style)
    }
    
    func reinitializeState() {
    // used by ^ resetARSession()
        selectedModel = nil
        alertItem = nil
        connectedPeers = []
        isPlaneVisualizationEnabled = false
        loadingProgress = 0.0
        userRole = .openSession
        isHostPermissionGranted = false
        deferredStartMultipeerServices = false
        pendingPeerToConnect = nil
        availableSessions = []
        selectedSession = nil
        sessionID  = ""
        sessionName = ""
        subscriptions = Set<AnyCancellable>()
        multipeerSession = nil
        shouldStartMultipeerSession = false
        arView = nil
        //models = []     // <----- just keep them for now. If really ramping this app up, you'd want to unload the models properly.
        placedAnchors = []
        anchorEntities = [:]
        pendingAnchorPayloads = [:]
        processedAnchorIDs = []
        anchorsAddedLocally = []
        pendingAnchors = [:]
        receivedWorldMap = nil
        activeEntity = nil
        initialScale = SIMD3<Float>(repeating: 1.0)
        initialRotation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        initialTouchWorldPosition = SIMD3<Float>(0, 0, 0)
        initialEntityWorldPosition = SIMD3<Float>(0, 0, 0)
        touchToEntityOffset = SIMD3<Float>(0, 0, 0)
        initialPanLocation = nil
        initialModelPosition = nil
    }
}



extension ARViewModel: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        print("session didAdd anchors: \(anchors.count)")
        for anchor in anchors {
            if processedAnchorIDs.contains(anchor.identifier) {
                print("Anchor \(anchor.identifier) already processed, skipping.")
                continue
            }

            if let planeAnchor = anchor as? ARPlaneAnchor, isPlaneVisualizationEnabled {
                if isPlaneVisualizationEnabled {
                    let planeEntity = makePlaneEntity(for: planeAnchor)
                    let anchorEntity = AnchorEntity(anchor: planeAnchor)
                    anchorEntity.addChild(planeEntity)
                    guard let arView = arView else {
                        print("Couldn't unwrap arView in func session(_ session: ARSession, didAdd anchors: [ARAnchor])")
                        return
                    }
                    arView.scene.addAnchor(anchorEntity)
                }
            } else if anchor.name != nil {
                if anchorsAddedLocally.contains(anchor.identifier) {
                    // Place the model immediately for locally added anchors
                    placeModel(for: anchor)
                    // Mark the anchor as processed
                    processedAnchorIDs.insert(anchor.identifier)
                    // Remove from anchorsAddedLocally since we've processed it
                    anchorsAddedLocally.remove(anchor.identifier)
                    
                    // If Host, send anchor with transform to peers
                    if userRole == .host || isHostPermissionGranted {
                        // Ensure that the anchor and transform are sent after the model is placed
                        sendAnchorWithTransform(anchor: anchor)
                    }
                } else if let payload = pendingAnchorPayloads[anchor.identifier] {
                    // Place the model with the provided transform
                    placeModel(for: anchor, modelID: payload.modelID, transformArray: payload.transform)
                    pendingAnchorPayloads.removeValue(forKey: anchor.identifier)
                    // Mark the anchor as processed
                    processedAnchorIDs.insert(anchor.identifier)
                    print("Placed model for anchor \(anchor.identifier) with transform.")
                } else {
                    // Store the anchor for later processing
                    pendingAnchors[anchor.identifier] = anchor
                    print("Stored anchor \(anchor.identifier) for later processing.")
                }
            } else {
                print("Received an anonymous anchor; ignoring.")
            }
        }
    }

    func sendAnchorWithTransform(anchor: ARAnchor) {
        if let anchorData = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true),
           let anchorEntity = self.anchorEntities[anchor.identifier],
           let modelEntity = anchorEntity.children.first as? ModelEntity {
            let modelID = modelEntity.name
            let transformArray = modelEntity.transform.matrix.toArray()
            let payload = AnchorTransformPayload(anchorData: anchorData, modelID: modelID, transform: transformArray)
            do {
                let data = try JSONEncoder().encode(payload)
                multipeerSession?.sendToAllPeers(data, dataType: .anchorWithTransform)
                print("Sent anchor and transform for model \(modelID) to peers")
            } catch {
                print("Failed to encode AnchorTransformPayload: \(error.localizedDescription)")
            }
        } else {
            print("Failed to prepare anchor and transform for sending.")
        }
    }

    private func makePlaneEntity(for planeAnchor: ARPlaneAnchor) -> ModelEntity {
        let mesh = MeshResource.generatePlane(width: 0.5, depth: 0.5)
        let material = SimpleMaterial(color: .blue.withAlphaComponent(0.2), isMetallic: false)
        let planeModel = ModelEntity(mesh: mesh, materials: [material])
        planeModel.name = "plane" // Set the name for easy removal
        return planeModel
    }

    func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
        // Safely unwrap multipeerSession and connectedPeers count
        guard let multipeerSession = multipeerSession,
              !((multipeerSession.session?.connectedPeers.isEmpty) != nil) else { return }

        do {
            let encodedData = try NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: true)
            multipeerSession.sendToAllPeers(encodedData, dataType: .collaborationData)
        } catch {
            print("Failed to encode collaboration data: \(error.localizedDescription)")
        }
    }

    // ARSessionDelegate method to observe feature points and apply received world map
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if hasSufficientFeaturePoints(), let worldMap = self.receivedWorldMap {
            applyReceivedWorldMap(worldMap)
            self.processPendingAnchors()
            self.receivedWorldMap = nil  // Clear the stored world map
        }
    }

    // Helper function to check if sufficient feature points have been detected
    func hasSufficientFeaturePoints() -> Bool {
        guard let arView = arView else {
            print("Couldn't unwrap arView in func hasSufficientFeaturePoints()")
            return false
        }
        guard let currentFrame = arView.session.currentFrame else { return false }
        let featurePointCount = currentFrame.rawFeaturePoints?.points.count ?? 0
        //print("Current feature point count: \(featurePointCount)")
        return featurePointCount >= minimumFeaturePointThreshold
    }

    // Function to apply the received world map after sufficient scanning
    func applyReceivedWorldMap(_ worldMap: ARWorldMap) {
        let configuration = ARWorldTrackingConfiguration()
        configuration.initialWorldMap = worldMap
        configuration.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .meshWithClassification
        }
        configuration.environmentTexturing = .automatic
        configuration.isCollaborationEnabled = true
        guard let arView = arView else {
            print("Couldn't unwrap arView in func applyReceivedWorldMap()")
            return
        }
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        print("Applied received ARWorldMap after sufficient scanning.")
    }
}



extension ARViewModel: MultipeerSessionDelegate {
    func receivedData(_ data: Data, from peerID: MCPeerID) {
        guard data.count > 1 else { return }
        guard arView != nil else {
            print("arView is not initialized yet.")
            return
        }
        guard let arView = arView else {
            print("arView could not be unwrapped in func func receivedData(_ data: Data, from peerID: MCPeerID) ")
            return
        }
        let dataTypeByte = data.first!
        let receivedData = data.advanced(by: 1)
        if let dataType = DataType(rawValue: dataTypeByte) {
            switch dataType {
            case .collaborationData:
                do {
                    if let collaborationData = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARSession.CollaborationData.self, from: receivedData) {
                        arView.session.update(with: collaborationData)
                    }
                } catch {
                    print("Failed to decode collaboration data: \(error.localizedDescription)")
                }
            case .modelTransform:
                do {
                    let payload = try JSONDecoder().decode(ModelTransformPayload.self, from: receivedData)
                    // Find the model entity with the matching modelID
                    if let modelEntity = findModelEntity(by: payload.modelID) {
                        // Reconstruct the simd_float4x4 from the array
                        let transformMatrix = simd_float4x4.fromArray(payload.transform)
                        modelEntity.transform.matrix = transformMatrix
                        print("Applied transform to model with ID \(payload.modelID)")
                    } else {
                        print("Model entity with ID \(payload.modelID) not found")
                    }
                } catch {
                    print("Failed to decode model transform: \(error.localizedDescription)")
                }
            case .anchorWithTransform:
                do {
                    let payload = try JSONDecoder().decode(AnchorTransformPayload.self, from: receivedData)
                    print("Received AnchorTransformPayload from \(peerID.displayName)")
                    if let anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARAnchor.self, from: payload.anchorData) {
                        if processedAnchorIDs.contains(anchor.identifier) {
                            print("Anchor \(anchor.identifier) already processed, updating model transform.")
                            if let anchorEntity = self.anchorEntities[anchor.identifier],
                               let modelEntity = anchorEntity.children.first(where: { $0.name == payload.modelID }) as? ModelEntity {
                                let transformMatrix = simd_float4x4.fromArray(payload.transform)
                                modelEntity.transform.matrix = transformMatrix
                                print("Updated model transform for \(payload.modelID)")
                            }
                        } else if let existingAnchor = arView.session.currentFrame?.anchors.first(where: { $0.identifier == anchor.identifier }) {
                            // Anchor already added, place the model
                            placeModel(for: existingAnchor, modelID: payload.modelID, transformArray: payload.transform)
                            processedAnchorIDs.insert(anchor.identifier)
                            print("Placed model for existing anchor \(anchor.identifier) with transform.")
                        } else {
                            // Store the payload for later processing
                            pendingAnchorPayloads[anchor.identifier] = payload
                            print("Stored payload for anchor \(anchor.identifier) for later processing.")
                            // Add the anchor to the session
                            arView.session.add(anchor: anchor)
                        }
                    } else {
                        print("Failed to decode ARAnchor from anchorData.")
                    }
                } catch {
                    print("Failed to decode AnchorTransformPayload: \(error.localizedDescription)")
                }
            case .anchor:
                do {
                    if let anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARAnchor.self, from: receivedData) {
                        arView.session.add(anchor: anchor)
                    }
                } catch {
                    print("Failed to decode anchor: \(error.localizedDescription)")
                }
            case .removeAnchors:
                do {
                    let ids = try JSONDecoder().decode([String].self, from: receivedData)
                    for idString in ids {
                        if let uuid = UUID(uuidString: idString) {
                            if let anchor = arView.session.currentFrame?.anchors.first(where: { $0.identifier == uuid }) {
                                arView.session.remove(anchor: anchor)
                            }
                            if let anchorEntity = anchorEntities[uuid] {
                                arView.scene.removeAnchor(anchorEntity)
                                anchorEntities.removeValue(forKey: uuid)
                                print("Removed anchor and entity with ID \(uuid)")
                            } else {
                                print("Anchor entity with ID \(uuid) not found")
                            }
                        }
                    }
                } catch {
                    print("Failed to decode anchor IDs for removal: \(error.localizedDescription)")
                }
            case .arWorldMap:
                do {
                    if let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: receivedData) {
                        print("Received ARWorldMap from \(peerID.displayName)")
                        // Reset AR Session before applying the world map
                        // resetARSession() // can try it, but I don't think this is a good idea
                        self.receivedWorldMap = worldMap
                        promptPeerToScanEnvironment()
                        observeFeaturePointsAndApplyWorldMap()
                    }
                } catch {
                    print("Failed to decode ARWorldMap: \(error.localizedDescription)")
                }
            case .permissionUpdate:
                do {
                    let isGranted = try JSONDecoder().decode(Bool.self, from: receivedData)
                    DispatchQueue.main.async {
                        self.isHostPermissionGranted = isGranted
                    }
                    print("Received permission update from Host: \(isGranted)")
                } catch {
                    print("Failed to decode permission update: \(error.localizedDescription)")
                }
            default:
                print("Unhandled data type received from \(peerID.displayName)")
            }
        } else {
            print("Unknown data type received from \(peerID.displayName)")
        }
    }

    func findModelEntity(by modelID: String) -> ModelEntity? {
        guard let arView = arView else {print("Couldn't unwrap arView in func findModelEntity()"); return nil}
        for anchor in arView.scene.anchors {
            if let modelEntity = anchor.findEntity(named: modelID) as? ModelEntity {
                return modelEntity
            }
        }
        return nil
    }

    func peerDidChangeState(peerID: MCPeerID, state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
                print("Connected to \(peerID.displayName)")

                // If host, send ARWorldMap and existing anchors with transforms
                if self.userRole == .host {
                    self.getCurrentWorldMap { worldMap in
                        if let worldMap = worldMap, self.validateWorldMap(worldMap) {
                            do {
                                let data = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
                                self.multipeerSession?.sendToPeer(data, peerID: peerID, dataType: .arWorldMap)
                                print("Sent ARWorldMap to \(peerID.displayName)")
                            } catch {
                                print("Error encoding ARWorldMap: \(error.localizedDescription)")
                            }
                        } else {
                            print("World map validation failed. Requesting user to scan more of the environment.")
                            // Optional: Prompt user to scan more or retry fetching the world map
                        }
                    }

                    // Send existing anchors with transforms
                    for anchor in self.placedAnchors {
                        if let anchorData = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true),
                          let anchorEntity = self.anchorEntities[anchor.identifier], let modelEntity = anchorEntity.children.first as? ModelEntity {
                            let modelID = modelEntity.name
                            let transformArray = modelEntity.transform.matrix.toArray()
                            let payload = AnchorTransformPayload(anchorData: anchorData, modelID: modelID, transform: transformArray)
                            do {
                                let data = try JSONEncoder().encode(payload)
                                self.multipeerSession?.sendToPeer(data, peerID: peerID, dataType: .anchorWithTransform)
                                print("Sent anchor and transform for model \(modelID) to \(peerID.displayName)")
                            } catch {
                                print("Failed to encode AnchorTransformPayload: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                // Send current permission state to the new peer
                self.sendPermissionUpdateToPeers(isGranted: self.isHostPermissionGranted)

            case .notConnected:
                if let index = self.connectedPeers.firstIndex(of: peerID) {
                    self.connectedPeers.remove(at: index)
                    print("Removed peer \(peerID.displayName) from connectedPeers.")
                }
                print("Disconnected from \(peerID.displayName)")

            case .connecting:
                print("Connecting to \(peerID.displayName)")

            @unknown default:
                print("Unknown state for \(peerID.displayName)")
            }
        }
    }

    func didReceiveInvitation(from peerID: MCPeerID, sessionID: String, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        if userRole == .openSession {
            print("Collaborate mode: accepting invitation from \(peerID.displayName)")
            invitationHandler(true, multipeerSession.session)
        } else if self.sessionID == sessionID {
            print("Accepting invitation from \(peerID.displayName) for session \(sessionID)")
            invitationHandler(true, multipeerSession.session)
        } else {
            print("Rejecting invitation from \(peerID.displayName) for session \(sessionID)")
            invitationHandler(false, nil)
        }
    }

    func foundPeer(peerID: MCPeerID, sessionID: String, sessionName: String) {
        DispatchQueue.main.async {
            if !self.availableSessions.contains(where: { $0.peerID == peerID }) {
                print("Adding found peer \(peerID.displayName) with session ID \(sessionID) and session name \(sessionName) to availableSessions.")
                self.availableSessions.append((peerID: peerID, sessionID: sessionID, sessionName: sessionName))
            }
        }
    }

    func lostPeer(peerID: MCPeerID) {
        DispatchQueue.main.async {
            if let index = self.availableSessions.firstIndex(where: { $0.peerID == peerID }) {
                self.availableSessions.remove(at: index)
            }
        }
    }

    // Helper function to get the current ARWorldMap
    func getCurrentWorldMap(completion: @escaping (ARWorldMap?) -> Void) {
        guard let arView = arView else {
            print("arView couldn't be unwrapped in func getCurrentWorldMap(completion: ...)")
            return
        }
        arView.session.getCurrentWorldMap { worldMap, error in
            if let error = error {
                print("Error getting current world map: \(error.localizedDescription)")
                completion(nil)
                return
            }

            if let worldMap = worldMap, self.validateWorldMap(worldMap) {
                print("World map validated successfully.")
                completion(worldMap)
            } else {
                print("World map validation failed. Requesting user to scan more of the environment.")
                self.promptPeerToScanEnvironment()
                completion(nil)
            }
        }
    }

    // Function to prompt the peer to scan the environment
    func promptPeerToScanEnvironment() {
        // Show UI prompt to the user
        DispatchQueue.main.async {
            self.alertItem = AlertItem(
                title: "Scan Environment",
                message: "Please move your device around to scan the environment a bit more for better alignment."
            )
        }
    }

    // Function to observe feature points and apply the world map
    func observeFeaturePointsAndApplyWorldMap() {
        guard let arView = arView else {
            print("arView couldn't be unwrapped in func observeFeaturePointsAndApplyWorldMap()")
            return
        }
        arView.session.delegate = self  // Ensure ARSessionDelegate is set
    }
}



extension simd_float4x4 {
    // Extracts the translation vector (position) from a 4x4 transformation matrix
    var translation: SIMD3<Float> {
        let translation = self.columns.3
        return SIMD3<Float>(translation.x, translation.y, translation.z)
    }
    func toArray() -> [Float] {
        let columns = [columns.0, columns.1, columns.2, columns.3]
        return columns.flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }
    static func fromArray(_ array: [Float]) -> simd_float4x4 {
        guard array.count == 16 else {
            print("Invalid transform array count: \(array.count). Expected 16.")
            return matrix_identity_float4x4
        }
        return simd_float4x4(
            SIMD4<Float>(array[0], array[1], array[2], array[3]),
            SIMD4<Float>(array[4], array[5], array[6], array[7]),
            SIMD4<Float>(array[8], array[9], array[10], array[11]),
            SIMD4<Float>(array[12], array[13], array[14], array[15])
        )
    }
}



struct ModelTransformPayload: Codable {
    let modelID: String
    let transform: [Float] // 16 elements representing the 4x4 matrix
}

enum DataType: UInt8 {
    case arWorldMap = 0
    case anchor = 1
    case collaborationData = 2
    case modelTransform = 3
    case removeAnchors = 4
    case anchorWithTransform = 5
    case permissionUpdate = 6
}

struct AnchorTransformPayload: Codable {
    let anchorData: Data  // Serialized ARAnchor
    let modelID: String
    let transform: [Float] // Model's transform matrix
}
