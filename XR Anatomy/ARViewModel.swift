import SwiftUI
import RealityKit
import ARKit
import Combine
import MultipeerConnectivity

enum UserRole {
    case host
    case viewer
    case openSession
}

class ARViewModel: NSObject, ObservableObject {
    // MARK: - Published
    @Published var selectedModel: Model? = nil
    @Published var alertItem: AlertItem?
    @Published var connectedPeers: [MCPeerID] = []
    @Published var isPlaneVisualizationEnabled = false
    @Published var loadingProgress: Float = 0.0
    @Published var userRole: UserRole = .openSession
    @Published var isHostPermissionGranted = false

    // Debug toggles
    @Published var areFeaturePointsEnabled = false { didSet { updateDebugOptions() }}
    @Published var isWorldOriginEnabled = false { didSet { updateDebugOptions() }}
    @Published var areAnchorOriginsEnabled = false { didSet { updateDebugOptions() }}
    @Published var isAnchorGeometryEnabled = false { didSet { updateDebugOptions() }}
    @Published var isSceneUnderstandingEnabled = false { didSet { updateDebugOptions() }}

    // Session management (for Join UI)
    @Published var availableSessions: [(peerID: MCPeerID, sessionID: String, sessionName: String)] = []
    @Published var selectedSession: (peerID: MCPeerID, sessionID: String, sessionName: String)?
    
    // MARK: - AR references
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
    var pendingPeerToConnect: MCPeerID?
    var sessionName: String = ""
    var sessionID: String = UUID().uuidString
    private var receivedWorldMap: ARWorldMap?
    private let minimumFeaturePointThreshold = 100
    private var subscriptions = Set<AnyCancellable>()
    private var deferredStartMultipeerServices = false
    private var shouldStartMultipeerSession = false

    // Gestures
    private var activeEntity: ModelEntity?
    private var initialScale: SIMD3<Float> = SIMD3<Float>(repeating: 1.0)
    private var initialRotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])
    private var initialTouchWorldPosition = SIMD3<Float>(0,0,0)
    private var initialEntityWorldPosition = SIMD3<Float>(0,0,0)
    private var touchToEntityOffset = SIMD3<Float>(0,0,0)

    override init() {
        super.init()
    }
    
    // MARK: - Load Models
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
                    guard let self = self else { return }
                    switch state {
                    case .loaded:
                        loadedModels += 1
                        self.loadingProgress = Float(loadedModels) / Float(totalModels)
                        if loadedModels == totalModels {
                            print("All models loaded.")
                            self.enableMultipeerServicesIfDeferred()
                        }
                    case .failed(let error):
                        self.alertItem = AlertItem(
                            title: "Failed to Load Model",
                            message: "\(mt.rawValue.capitalized): \(error.localizedDescription)"
                        )
                    default:
                        break
                    }
                }
                .store(in: &subscriptions)
        }
    }

    // MARK: - Setup AR
    func setupARView(_ arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
        updateDebugOptions()

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .meshWithClassification
        }
        config.environmentTexturing = .automatic
        config.isCollaborationEnabled = true
        arView.session.run(config)

        arView.environment.sceneUnderstanding.options = .default
        printSceneUnderstandingOptions(for: arView)

        // Add gesture recognizers
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        let rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))

        arView.addGestureRecognizer(tapGesture)
        arView.addGestureRecognizer(panGesture)
        arView.addGestureRecognizer(pinchGesture)
        arView.addGestureRecognizer(rotationGesture)

        if shouldStartMultipeerSession {
            startMultipeerServices()
        }
    }

    func printSceneUnderstandingOptions(for arView: ARView) {
        let options = arView.environment.sceneUnderstanding.options
        print("\nScene Understanding Options:")
        if options.contains(.physics)           { print("- Physics") }
        if options.contains(.receivesLighting)  { print("- Receives lighting") }
        if options.contains(.occlusion)         { print("- Occlusion") }
        if options.contains(.collision)         { print("- Collision") }
        if options.isEmpty                      { print("- None") }
    }

    // MARK: - Multipeer
    func startMultipeerServices() {
        guard multipeerSession == nil else { return }
        if userRole == .host || userRole == .openSession {
            guard arView != nil else {
                deferredStartMultipeerServices = true
                return
            }
        }
        multipeerSession = MultipeerSession(sessionID: sessionID, sessionName: sessionName, userRole: userRole)
        multipeerSession.delegate = self
        multipeerSession.start()
        print("MultipeerSession started with ID \(sessionID).")

        if let peer = pendingPeerToConnect {
            multipeerSession.invitePeer(peer, sessionID: sessionID)
            pendingPeerToConnect = nil
        }
    }

    func connectToSession(peerID: MCPeerID) {
        if let m = multipeerSession {
            m.invitePeer(peerID, sessionID: sessionID)
        } else {
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
        multipeerSession?.invitePeer(peerID, sessionID: sessionID)
    }

    func toggleHostPermissions() {
        isHostPermissionGranted.toggle()
        sendPermissionUpdateToPeers(isGranted: isHostPermissionGranted)
        if isHostPermissionGranted {
            syncSceneData()
        }
    }

    func sendPermissionUpdateToPeers(isGranted: Bool) {
        do {
            let data = try JSONEncoder().encode(isGranted)
            multipeerSession?.sendToAllPeers(data, dataType: .permissionUpdate)
        } catch {
            print("Failed to encode permission update: \(error)")
        }
    }

    // MARK: - GESTURES
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        guard userRole != .viewer || isHostPermissionGranted else { return }
        guard let arView = arView else { return }

        let location = sender.location(in: arView)
        let results = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any)

        if let result = results.first,
           let model = selectedModel,
           let _ = model.modelEntity {

            // Create a unique anchor name and ARAnchor
            let uniqueID = UUID().uuidString
            let anchorName = "\(model.modelType.rawValue)_\(uniqueID)"
            let anchor = ARAnchor(name: anchorName, transform: result.worldTransform)
            arView.session.add(anchor: anchor)

            placedAnchors.append(anchor)
            anchorsAddedLocally.insert(anchor.identifier)

            // Optionally send the anchor transform
            sendAnchorWithTransform(anchor: anchor)
        }
        printSceneUnderstandingOptions(for: arView)
    }

    @objc func handlePan(_ sender: UIPanGestureRecognizer) {
        guard userRole != .viewer || isHostPermissionGranted else { return }
        guard let arView = arView else { return }

        let location = sender.location(in: arView)
        if sender.state == .began {
            activeEntity = findClosestModelEntity(to: location, in: arView)
            if let entity = activeEntity {
                if let raycast = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any).first {
                    initialTouchWorldPosition = raycast.worldTransform.position
                    initialEntityWorldPosition = entity.transform.translation
                    touchToEntityOffset = initialEntityWorldPosition - initialTouchWorldPosition
                }
            }
        }
        guard let entity = activeEntity else { return }

        if sender.state == .changed {
            if let raycast = arView.raycast(from: location, allowing: .estimatedPlane, alignment: .any).first {
                let currentTouchPos = raycast.worldTransform.position
                let newPos = currentTouchPos + touchToEntityOffset
                var newTransform = entity.transform
                newTransform.translation = newPos
                entity.transform = newTransform
            }
        }
        if sender.state == .ended {
            sendModelTransform(entity)
            activeEntity = nil
        }
    }

    @objc func handlePinch(_ sender: UIPinchGestureRecognizer) {
        guard userRole != .viewer || isHostPermissionGranted else { return }
        let location = sender.location(in: arView)
        if sender.state == .began {
            activeEntity = findClosestModelEntity(to: location, in: arView)
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

    @objc func handleRotation(_ sender: UIRotationGestureRecognizer) {
        guard userRole != .viewer || isHostPermissionGranted else { return }
        let location = sender.location(in: arView)

        if sender.state == .began {
            activeEntity = findClosestModelEntity(to: location, in: arView)
            if let modelType = selectedModel?.modelType,
               modelType.shouldRotateAroundZAxis {
                initialRotation = activeEntity?.transform.rotation
                    ?? simd_quatf(angle: 0, axis: [0,0,1])
            } else {
                initialRotation = activeEntity?.transform.rotation
                    ?? simd_quatf(angle: 0, axis: [0,1,0])
            }
        }
        guard let entity = activeEntity else { return }

        if sender.state == .changed {
            let rotationAngle = Float(sender.rotation) * -1.0
            let axis = (selectedModel?.modelType.shouldRotateAroundZAxis ?? false)
                ? SIMD3<Float>(0,0,1)
                : SIMD3<Float>(0,1,0)
            let delta = simd_quatf(angle: rotationAngle, axis: axis)
            entity.transform.rotation = initialRotation * delta
        }
        if sender.state == .ended {
            sender.rotation = 0
            sendModelTransform(entity)
            activeEntity = nil
        }
    }

    private func findClosestModelEntity(to location: CGPoint, in arView: ARView?) -> ModelEntity? {
        guard let arView = arView else { return nil }
        return arView.entity(at: location) as? ModelEntity
    }

    func sendModelTransform(_ modelEntity: ModelEntity) {
        let modelID = modelEntity.name
        guard !modelID.isEmpty else { return }
        let transformMatrix = modelEntity.transform.matrix
        let transformArray = transformMatrix.toArray()

        do {
            let payload = ModelTransformPayload(modelID: modelID, transform: transformArray)
            let data = try JSONEncoder().encode(payload)
            multipeerSession?.sendToAllPeers(data, dataType: .modelTransform)
        } catch {
            print("Failed to encode model transform: \(error)")
        }
    }

    // MARK: - Scene Sync
    func syncSceneData() {
        print("Sync initiated (collaboration data also auto-shares).")
    }

    // Clear local anchors
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

        // figure out the final model ID
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

        // We can't pass a RealityKit Transform to AnchorEntity(...) directly,
        // so we create an empty anchor and set its transform manually:
        let anchorEntity = AnchorEntity()

        // Convert ARAnchor's transform (simd_float4x4) into a RealityKit Transform
        let transformMatrix = anchor.transform
        let realityTransform = Transform(matrix: transformMatrix)
        anchorEntity.transform = realityTransform

        // Clone the model entity
        let clone = modelEntity.clone(recursive: true)
        clone.name = finalModelID

        if let tarr = transformArray {
            let newMatrix = simd_float4x4.fromArray(tarr)
            clone.transform.matrix = newMatrix
        } else {
            // default scale if no transform specified
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

    func updateDebugOptions() {
        var opts: ARView.DebugOptions = []
        if areFeaturePointsEnabled       { opts.insert(.showFeaturePoints) }
        if isWorldOriginEnabled          { opts.insert(.showWorldOrigin) }
        if areAnchorOriginsEnabled       { opts.insert(.showAnchorOrigins) }
        if isAnchorGeometryEnabled       { opts.insert(.showAnchorGeometry) }
        if isSceneUnderstandingEnabled   { opts.insert(.showSceneUnderstanding) }
        arView?.debugOptions = opts
    }

    func togglePlaneVisualization(isEnabled: Bool) {
        guard let arView = arView else { return }
        if isEnabled {
            if let config = arView.session.configuration {
                arView.session.run(config, options: [.removeExistingAnchors])
            }
        } else {
            removeAllPlaneEntities()
        }
    }

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

    func validateWorldMap(_ wm: ARWorldMap) -> Bool {
        let minAnchorCount = 5
        let minFPCount = 100
        // ARWorldMap.rawFeaturePoints => ARPointCloud
        // There's no .count property, so use .points.count:
        let fpCount = wm.rawFeaturePoints.points.count

        return wm.anchors.count >= minAnchorCount && fpCount >= minFPCount
    }

    func stopMultipeerServices() {
        multipeerSession?.disconnect()
        multipeerSession?.delegate = nil
        multipeerSession = nil
        print("Multipeer services stopped.")
    }

    func resetARSession() {
        guard let arView = arView else { return }
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        multipeerSession?.delegate = nil
        NotificationCenter.default.removeObserver(self)
        arView.session.delegate = nil

        arView.session.pause()
        arView.scene.anchors.removeAll()

        if let configuration = arView.session.configuration {
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
        reinitializeState()

        // Reassign delegate
        arView.session.delegate = self
    }

    func reinitializeState() {
        selectedModel = nil
        alertItem = nil
        connectedPeers = []
        isPlaneVisualizationEnabled = false
        loadingProgress = 0
        userRole = .openSession
        isHostPermissionGranted = false
        deferredStartMultipeerServices = false
        pendingPeerToConnect = nil
        availableSessions = []
        selectedSession = nil
        sessionID = ""
        sessionName = ""
        subscriptions.removeAll()
        multipeerSession = nil
        shouldStartMultipeerSession = false

        // Keep ARView as is or nil out
        placedAnchors.removeAll()
        anchorEntities.removeAll()
        pendingAnchorPayloads.removeAll()
        processedAnchorIDs.removeAll()
        anchorsAddedLocally.removeAll()
        pendingAnchors.removeAll()
        receivedWorldMap = nil
        activeEntity = nil
        initialScale = SIMD3<Float>(repeating: 1)
        initialRotation = simd_quatf(angle: 0, axis: [0,1,0])
        initialTouchWorldPosition = .zero
        initialEntityWorldPosition = .zero
        touchToEntityOffset = .zero
    }
}

// MARK: - ARSessionDelegate
extension ARViewModel: ARSessionDelegate {
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if processedAnchorIDs.contains(anchor.identifier) { continue }

            // If plane anchor
            if let planeAnchor = anchor as? ARPlaneAnchor, isPlaneVisualizationEnabled {
                // Make a plane entity
                let planeEntity = makePlaneEntity(for: planeAnchor)

                // Instead of AnchorEntity(world: ...), create empty anchor, set transform
                let anchorEntity = AnchorEntity()
                let anchorTransform = Transform(matrix: planeAnchor.transform)
                anchorEntity.transform = anchorTransform

                anchorEntity.addChild(planeEntity)
                arView?.scene.addAnchor(anchorEntity)

            } else if anchor.name != nil {
                if anchorsAddedLocally.contains(anchor.identifier) {
                    placeModel(for: anchor)
                    processedAnchorIDs.insert(anchor.identifier)
                    anchorsAddedLocally.remove(anchor.identifier)

                    if userRole == .host || isHostPermissionGranted {
                        sendAnchorWithTransform(anchor: anchor)
                    }
                } else if let payload = pendingAnchorPayloads[anchor.identifier] {
                    placeModel(for: anchor, modelID: payload.modelID, transformArray: payload.transform)
                    pendingAnchorPayloads.removeValue(forKey: anchor.identifier)
                    processedAnchorIDs.insert(anchor.identifier)
                } else {
                    // store for later
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
                multipeerSession?.sendToAllPeers(data, dataType: .anchorWithTransform)
            } catch {
                print("Failed to encode AnchorTransformPayload: \(error)")
            }
        }
    }

    private func makePlaneEntity(for planeAnchor: ARPlaneAnchor) -> ModelEntity {
        // We can't pass a SwiftUI Color, but we can pass a SimpleMaterial.Color that wraps a UIColor
        let mesh = MeshResource.generatePlane(width: 0.5, depth: 0.5)
        let uiColor = Color.blue
        let matColor = SimpleMaterial.Color(uiColor)
        let material = SimpleMaterial(color: matColor, isMetallic: false)

        let plane = ModelEntity(mesh: mesh, materials: [material])
        plane.name = "plane"
        return plane
    }

    func session(_ session: ARSession, didOutputCollaborationData data: ARSession.CollaborationData) {
        guard let m = multipeerSession, !(m.session?.connectedPeers.isEmpty ?? true) else { return }
        do {
            let encoded = try NSKeyedArchiver.archivedData(withRootObject: data, requiringSecureCoding: true)
            m.sendToAllPeers(encoded, dataType: .collaborationData)
        } catch {
            print("Failed to encode collab data: \(error)")
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if hasSufficientFeaturePoints(), let wm = receivedWorldMap {
            applyReceivedWorldMap(wm)
            processPendingAnchors()
            receivedWorldMap = nil
        }
    }

    func hasSufficientFeaturePoints() -> Bool {
        guard let frame = arView?.session.currentFrame,
              let featurePoints = frame.rawFeaturePoints else { return false }
        let count = featurePoints.points.count
        return count >= minimumFeaturePointThreshold
    }

    func applyReceivedWorldMap(_ wm: ARWorldMap) {
        let config = ARWorldTrackingConfiguration()
        config.initialWorldMap = wm
        config.planeDetection = [.horizontal, .vertical]
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .meshWithClassification
        }
        config.environmentTexturing = .automatic
        config.isCollaborationEnabled = true

        arView?.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        print("Applied received ARWorldMap")
    }
}

// MARK: - MultipeerSessionDelegate
extension ARViewModel: MultipeerSessionDelegate {
    func receivedData(_ data: Data, from peerID: MCPeerID) {
        guard data.count > 1 else { return }
        guard let arView = arView else { return }

        let dataTypeByte = data.first!
        let rest = data.advanced(by: 1)
        if let dt = DataType(rawValue: dataTypeByte) {
            switch dt {
            case .collaborationData:
                do {
                    if let c = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARSession.CollaborationData.self, from: rest) {
                        arView.session.update(with: c)
                    }
                } catch {
                    print("Failed to decode collab data: \(error)")
                }
            case .modelTransform:
                do {
                    let p = try JSONDecoder().decode(ModelTransformPayload.self, from: rest)
                    if let me = findModelEntity(by: p.modelID) {
                        let mat = simd_float4x4.fromArray(p.transform)
                        me.transform.matrix = mat
                    }
                } catch {
                    print("Failed to decode model transform: \(error)")
                }
            case .anchorWithTransform:
                do {
                    let pl = try JSONDecoder().decode(AnchorTransformPayload.self, from: rest)
                    if let anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARAnchor.self, from: pl.anchorData) {
                        if processedAnchorIDs.contains(anchor.identifier) {
                            if let ae = anchorEntities[anchor.identifier],
                               let me = ae.children.first(where: { $0.name == pl.modelID }) as? ModelEntity {
                                let mat = simd_float4x4.fromArray(pl.transform)
                                me.transform.matrix = mat
                            }
                        } else if let existing = arView.session.currentFrame?.anchors.first(where: { $0.identifier == anchor.identifier }) {
                            placeModel(for: existing, modelID: pl.modelID, transformArray: pl.transform)
                            processedAnchorIDs.insert(anchor.identifier)
                        } else {
                            pendingAnchorPayloads[anchor.identifier] = pl
                            arView.session.add(anchor: anchor)
                        }
                    }
                } catch {
                    print("Failed to decode AnchorTransformPayload: \(error)")
                }
            case .anchor:
                do {
                    if let a = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARAnchor.self, from: rest) {
                        arView.session.add(anchor: a)
                    }
                } catch {
                    print("Failed to decode anchor: \(error)")
                }
            case .removeAnchors:
                do {
                    let ids = try JSONDecoder().decode([String].self, from: rest)
                    for idstr in ids {
                        if let u = UUID(uuidString: idstr),
                           let an = arView.session.currentFrame?.anchors.first(where: { $0.identifier == u }) {
                            arView.session.remove(anchor: an)
                        }
                        if let u = UUID(uuidString: idstr),
                           let ae = anchorEntities[u] {
                            arView.scene.removeAnchor(ae)
                            anchorEntities.removeValue(forKey: u)
                        }
                    }
                } catch {
                    print("Failed to decode anchor removal IDs: \(error)")
                }
            case .arWorldMap:
                do {
                    if let wm = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: rest) {
                        self.receivedWorldMap = wm
                        promptPeerToScanEnvironment()
                        observeFeaturePointsAndApplyWorldMap()
                    }
                } catch {
                    print("Failed to decode ARWorldMap: \(error)")
                }
            case .permissionUpdate:
                do {
                    let isGranted = try JSONDecoder().decode(Bool.self, from: rest)
                    DispatchQueue.main.async {
                        self.isHostPermissionGranted = isGranted
                    }
                } catch {
                    print("Failed to decode permission update: \(error)")
                }
            case .textMessage:
                print("text")
            }
        } else {
            print("Unknown data type from \(peerID.displayName)")
        }
    }

    func findModelEntity(by modelID: String) -> ModelEntity? {
        guard let arView = arView else { return nil }
        for anchor in arView.scene.anchors {
            if let me = anchor.findEntity(named: modelID) as? ModelEntity {
                return me
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

                // If host, share a world map or anchors
                if self.userRole == .host {
                    self.getCurrentWorldMap { wm in
                        if let w = wm, self.validateWorldMap(w) {
                            do {
                                let d = try NSKeyedArchiver.archivedData(withRootObject: w, requiringSecureCoding: true)
                                self.multipeerSession?.sendToPeer(d, peerID: peerID, dataType: .arWorldMap)
                            } catch {
                                print("Error encoding ARWorldMap: \(error)")
                            }
                        }
                        // also send existing anchors
                        for anchor in self.placedAnchors {
                            if let ancData = try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true),
                               let ae = self.anchorEntities[anchor.identifier],
                               let me = ae.children.first as? ModelEntity {
                                let modelID = me.name
                                let tarr = me.transform.matrix.toArray()
                                let payload = AnchorTransformPayload(anchorData: ancData, modelID: modelID, transform: tarr)
                                do {
                                    let encoded = try JSONEncoder().encode(payload)
                                    self.multipeerSession?.sendToPeer(encoded, peerID: peerID, dataType: .anchorWithTransform)
                                } catch {
                                    print("Failed to encode anchor transform: \(error)")
                                }
                            }
                        }
                    }
                    self.sendPermissionUpdateToPeers(isGranted: self.isHostPermissionGranted)
                }

            case .notConnected:
                if let i = self.connectedPeers.firstIndex(of: peerID) {
                    self.connectedPeers.remove(at: i)
                }

            case .connecting:
                print("Connecting to \(peerID.displayName)")

            @unknown default:
                print("Unknown state for \(peerID.displayName)")
            }
        }
    }

    func didReceiveInvitation(from peerID: MCPeerID, sessionID: String,
                              invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        if userRole == .openSession {
            invitationHandler(true, multipeerSession.session)
        } else if self.sessionID == sessionID {
            invitationHandler(true, multipeerSession.session)
        } else {
            invitationHandler(false, nil)
        }
    }

    func foundPeer(peerID: MCPeerID, sessionID: String, sessionName: String) {
        DispatchQueue.main.async {
            if !self.availableSessions.contains(where: { $0.peerID == peerID }) {
                self.availableSessions.append((peerID, sessionID, sessionName))
            }
        }
    }

    func lostPeer(peerID: MCPeerID) {
        DispatchQueue.main.async {
            if let i = self.availableSessions.firstIndex(where: { $0.peerID == peerID }) {
                self.availableSessions.remove(at: i)
            }
        }
    }

    func getCurrentWorldMap(completion: @escaping (ARWorldMap?) -> Void) {
        arView?.session.getCurrentWorldMap { map, err in
            if let e = err {
                print("Error getting world map: \(e)")
                completion(nil)
                return
            }
            if let m = map, self.validateWorldMap(m) {
                completion(m)
            } else {
                print("World map invalid.")
                self.promptPeerToScanEnvironment()
                completion(nil)
            }
        }
    }

    func promptPeerToScanEnvironment() {
        DispatchQueue.main.async {
            self.alertItem = AlertItem(
                title: "Scan Environment",
                message: "Please move your device to scan the environment for better alignment."
            )
        }
    }

    func observeFeaturePointsAndApplyWorldMap() {
        // We'll reassign self as the session delegate, so we can watch rawFeaturePoints
        arView?.session.delegate = self
    }
}
