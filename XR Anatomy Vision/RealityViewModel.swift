// RealityViewModel.swift
import SwiftUI
import RealityKit
import Combine
import MultipeerConnectivity
import ObjectiveC.runtime

class RealityViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var selectedModel: Model? = nil
    @Published var alertItem: AlertItem?
    @Published var connectedPeers: [MCPeerID] = []
    @Published var loadingProgress: Float = 0.0

    // MARK: - Properties
    private var subscriptions = Set<AnyCancellable>()
    private var multipeerSession: MultipeerSession?
    private var shouldStartMultipeerSession = false
    var models: [Model] = []
    var placedEntities: [UUID: Entity] = [:]
    var realityViewContent: RealityViewContent?
    var updateSubscription: EventSubscription?
    private var modelCache: [String: ModelEntity] = [:]


    // Gesture tracking properties
    private var activeEntity: ModelEntity?
    private var initialScale: SIMD3<Float> = SIMD3<Float>(repeating: 1.0)
    private var initialRotation: simd_quatf = simd_quatf()
    private var initialPosition: SIMD3<Float> = SIMD3<Float>(repeating: 0.0)
 
    
//    @MainActor
//    func addModelForTesting() async {
//        while models.isEmpty {
//                try? await Task.sleep(for: .milliseconds(10))
//            }
//        guard let firstModel = models.first, let modelEntity = firstModel.modelEntity else {
//            print("No models loaded or first model is unavailable.")
//            return
//        }
//
//        let uniqueID = UUID()
//        let modelClone = modelEntity.clone(recursive: true)
//        modelClone.name = uniqueID.uuidString
//        modelClone.generateCollisionShapes(recursive: true)
//        modelClone.position = SIMD3<Float>(0, 0, -0.5) // Position it 0.5 meters in front of the camera
//        modelClone.scale = SIMD3<Float>(0.1, 0.1, 0.1) // Adjust scale as needed
//
//        placedEntities[uniqueID] = modelClone
//        realityViewContent?.entities.append(modelClone)
//
//        print("Added model for testing: \(modelClone.name) at position \(modelClone.position)")
//    }
    // MARK: - Setup RealityView Content
    func setupRealityViewContent(_ content: inout RealityViewContent) async {
        self.realityViewContent = content

        // Prepare a list of entities to add
        var newEntities: [AnchorEntity] = []

        for entity in placedEntities.values {
            if await entity.parent == nil {
                let anchor = await AnchorEntity(world: entity.position)
                await anchor.addChild(entity)
                newEntities.append(anchor)
            } else if let anchor = entity as? AnchorEntity {
                newEntities.append(anchor)
            } else {
                // Wrap non-anchor entities into an AnchorEntity
                let newAnchor = await AnchorEntity()
                await newAnchor.addChild(entity)
                newEntities.append(newAnchor)
            }
        }

        // Update content
        content.entities.append(contentsOf: newEntities)
        print("Entities added to RealityViewContent: \(content.entities.count)")
    }

    // MARK: - Lifecycle Methods
    func onAppear() {
        startMultipeerServices()
    }

    func onDisappear() {
        // Handle any necessary cleanup
        updateSubscription?.cancel()
        updateSubscription = nil
    }

    // MARK: - Load Models
    func loadModel(named name: String) async throws -> ModelEntity {
        if let cachedModel = modelCache[name] {
            return cachedModel
        }
        let modelEntity = try await ModelEntity(named: name)
        modelCache[name] = modelEntity
        return modelEntity
    }
    
    func loadModels() {
        guard models.isEmpty else { return } // Prevent duplicate loading

        let modelTypes = ModelType.allCases()
        let totalModels = modelTypes.count
        var loadedModels = 0

        for modelType in modelTypes {
            let model = Model(modelType: modelType)
            models.append(model)

            model.$loadingState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    switch state {
                    case .loaded:
                        loadedModels += 1
                        self?.loadingProgress = Float(loadedModels) / Float(totalModels)

                        if loadedModels == totalModels {
                                                print("All models loaded successfully.")
                                                self?.enableMultipeerServicesIfDeferred()

                                                // Add test model after all models are loaded
//                                                Task {
//                                                    await self?.addModelForTesting()
//                                                }
                                            }
                    case .failed(let error):
                        self?.alertItem = AlertItem(
                            title: "Failed to Load Model",
                            message: "Model \(modelType.rawValue.capitalized): \(error.localizedDescription)"
                        )
                    default:
                        break
                    }
                }
                .store(in: &subscriptions)
        }
    }
    
    

    // MARK: - Multipeer Control
    func startMultipeerServices() {
        guard multipeerSession == nil else { return } // Ensure single initialization
        multipeerSession = MultipeerSession()
        multipeerSession?.delegate = self
        print("Multipeer services initialized.")
        shouldStartMultipeerSession = false
        print("Multipeer services started.")
    }

    func deferMultipeerServicesUntilModelsLoad() {
        shouldStartMultipeerSession = true
    }

    func enableMultipeerServicesIfDeferred() {
        if shouldStartMultipeerSession {
            startMultipeerServices()
        }
    }

    // MARK: - Gesture Handling
    func setInitialGestureState(for entity: ModelEntity) {
        activeEntity = entity
        initialScale = entity.scale
        initialRotation = entity.orientation
        initialPosition = entity.position
    }
    
    func createGestures() -> some Gesture {
        let tapGesture = TapGesture()
            .onEnded { [weak self] in
                Task { @MainActor in
                    await self?.handleTapGesture()
                }
            }

        let pinchGesture = MagnificationGesture()
            .onChanged { [weak self] scale in
                self?.handlePinchGesture(scale)
            }

        let dragGesture = DragGesture()
            .onChanged { [weak self] value in
                self?.handleDragGesture(value)
            }

        let rotationGesture = RotationGesture()
            .onChanged { [weak self] angle in
                self?.handleRotationGesture(angle)
            }

        return SimultaneousGesture(tapGesture, pinchGesture)
            .simultaneously(with: dragGesture)
            .simultaneously(with: rotationGesture)
    }

    // MARK: - Gesture Handlers
    @MainActor
    func handleTapGesture() async {
        guard let modelName = selectedModel?.modelType.rawValue else {
            print("No model selected for placement.")
            return
        }

        let position = SIMD3<Float>(0, 0, -0.5) // Example: Place in front of the user
        await placeModel(named: modelName)
    }

    func handlePinchGesture(_ scale: CGFloat) {
        guard let activeEntity = activeEntity else { return }
        let newScale = initialScale * Float(scale) // Multiply each component of SIMD3<Float> by the scalar
        activeEntity.scale = newScale
        print("Pinch scale applied: \(newScale)")
    }

    func handleRotationGesture(_ angle: Angle) {
        guard let activeEntity = activeEntity else { return }
        let newRotation = simd_quatf(angle: Float(angle.radians), axis: [0, 1, 0])
        activeEntity.orientation = initialRotation * newRotation
        print("Rotation applied: \(newRotation)")
    }

    func handleDragGesture(_ value: DragGesture.Value) {
        guard let activeEntity = activeEntity else { return }
        let translation = SIMD3<Float>(Float(value.translation.width), 0, Float(value.translation.height))
        activeEntity.position = initialPosition + translation
        print("Dragged to position: \(activeEntity.position)")
    }

    // MARK: - Scene Update Handler
    func sceneDidUpdate(_ event: SceneEvents.Update) {
        // Perform per-frame updates here if needed
    }
    
    @MainActor
    func placeModel(named modelName: String) async {
        print("Attempting to place model: \(modelName)")
        do {
            // Load the model
            let modelEntity = try await loadModel(named: modelName)
            print("Model \(modelName) loaded successfully")

            // Configure gesture components
            let bounds = modelEntity.visualBounds(relativeTo: nil)
            let collisionBox = ShapeResource.generateBox(
                width: bounds.extents.x,
                height: bounds.extents.y,
                depth: bounds.extents.z
            )
            modelEntity.components.set(CollisionComponent(shapes: [collisionBox]))
            modelEntity.components.set(InputTargetComponent())

            // Position and anchor the model
            modelEntity.position = SIMD3<Float>(0, -bounds.min.y, -0.5)
            let anchor = AnchorEntity()
            anchor.addChild(modelEntity)
            print("Model \(modelName) anchored at position: \(modelEntity.position)")

            // Update RealityViewContent
            placedEntities[UUID()] = anchor
            if let realityViewContent = realityViewContent {
                realityViewContent.entities.append(anchor)
                print("Anchor added to RealityViewContent")
            }
        } catch {
            print("Failed to place model \(modelName): \(error.localizedDescription)")
        }
    }
    
    // MARK: - Send Model Transform
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

    // MARK: - Multipeer Connectivity
    func sendEntityToPeers(_ entity: ModelEntity) {
        guard let modelType = entity.getModelType()?.rawValue else {
            print("Entity does not have a valid model type.")
            return
        }

        let modelID = entity.name
        guard !modelID.isEmpty else {
            print("Entity does not have a valid name (ID).")
            return
        }

        // Construct the transform data
        let transformData = TransformData(
            position: [entity.position.x, entity.position.y, entity.position.z],
            orientation: [entity.orientation.vector.x, entity.orientation.vector.y, entity.orientation.vector.z, entity.orientation.vector.w],
            scale: [entity.scale.x, entity.scale.y, entity.scale.z]
        )

        // Construct the shared entity data
        let entityData = SharedEntityData(
            modelType: modelType,
            uniqueID: modelID,
            transform: transformData
        )

        do {
            // Encode the entity data
            let encodedEntityData = try JSONEncoder().encode(entityData)

            // Prefix the data with an existing DataType case (e.g., modelTransform)
            var prefixedData = Data([DataType.modelTransform.rawValue])
            prefixedData.append(encodedEntityData)

            // Send to all peers
            multipeerSession?.sendToAllPeers(prefixedData, dataType: .modelTransform)
            print("Sent entity data for modelID: \(modelID) using modelTransform prefix")
        } catch {
            print("Failed to encode or send entity data: \(error.localizedDescription)")
        }
    }
    // MARK: - Find Model Entity
    func findModelEntity(by modelID: String) -> ModelEntity? {
        for entity in placedEntities.values {
            if let modelEntity = entity.findEntity(named: modelID) as? ModelEntity {
                return modelEntity
            }
        }
        return nil
    }

    // MARK: - Clear All Models
    func clearAllModels() {
        realityViewContent?.entities.removeAll()
        placedEntities.removeAll()
        print("All models have been cleared from the scene.")
    }

    // MARK: - Apply Received Entity Data
    @MainActor
    func applyReceivedEntityData(_ entityData: SharedEntityData) {
        if let existingEntity = findModelEntity(by: entityData.uniqueID) {
            // Update existing entity
            existingEntity.transform = Transform(
                scale: SIMD3<Float>(entityData.transform.scale[0], entityData.transform.scale[1], entityData.transform.scale[2]),
                rotation: simd_quatf(vector: SIMD4<Float>(entityData.transform.orientation[0], entityData.transform.orientation[1], entityData.transform.orientation[2], entityData.transform.orientation[3])),
                translation: SIMD3<Float>(entityData.transform.position[0], entityData.transform.position[1], entityData.transform.position[2])
            )
        } else {
            // Place new entity
            guard let model = models.first(where: { $0.modelType.rawValue == entityData.modelType }),
                  let modelEntity = model.modelEntity else {
                print("Model not found for type \(entityData.modelType)")
                return
            }

            let modelClone = modelEntity.clone(recursive: true)
            modelClone.name = entityData.uniqueID
            modelClone.transform = Transform(
                scale: SIMD3<Float>(entityData.transform.scale[0], entityData.transform.scale[1], entityData.transform.scale[2]),
                rotation: simd_quatf(vector: SIMD4<Float>(entityData.transform.orientation[0], entityData.transform.orientation[1], entityData.transform.orientation[2], entityData.transform.orientation[3])),
                translation: SIMD3<Float>(entityData.transform.position[0], entityData.transform.position[1], entityData.transform.position[2])
            )
            modelClone.setModelType(model.modelType) // Custom method to associate modelType

            placedEntities[UUID(uuidString: entityData.uniqueID) ?? UUID()] = modelClone

            realityViewContent?.entities.append(modelClone)
        }
    }
}

// MARK: - MultipeerSessionDelegate
extension RealityViewModel: MultipeerSessionDelegate {
    func receivedData(_ data: Data, from peerID: MCPeerID) {
        guard data.count > 1 else { return }
        let dataTypeByte = data.first!
        let receivedData = data.advanced(by: 1)

        if let dataType = DataType(rawValue: dataTypeByte) {
            switch dataType {
            case .arWorldMap:
                print("Received ARWorldMap data. Ignored for now.")
            case .anchor:
                print("Received anchor data. Ignored for now.")
            case .collaborationData:
                print("Received collaboration data. Ignored for now.")
//                handleCollaborationData(receivedData)
            case .modelTransform:
                handleModelTransform(receivedData)
            default:
                print("Unhandled data type.")
            }
        } else {
            print("Unknown data type received from \(peerID.displayName)")
        }
    }
    
    func handleModelTransform(_ data: Data) {
        do {
            let payload = try JSONDecoder().decode(ModelTransformPayload.self, from: data)
            Task { @MainActor in
                if let modelEntity = findModelEntity(by: payload.modelID) {
                    let transformMatrix = simd_float4x4.fromArray(payload.transform)
                    modelEntity.transform.matrix = transformMatrix
                    print("Applied transform to model with ID \(payload.modelID)")
                } else {
                    print("Model entity with ID \(payload.modelID) not found")
                }
            }
        } catch {
            print("Failed to decode ModelTransformPayload: \(error)")
        }
    }
    
    func receivedEntityData(_ data: Data) {
        do {
            let entityData = try JSONDecoder().decode(SharedEntityData.self, from: data)
            Task { @MainActor in
                self.applyReceivedEntityData(entityData)
            }
        } catch {
            print("Failed to decode entity data: \(error.localizedDescription)")
        }
    }

    func updateModelTransform(_ payload: ModelTransformPayload) {
        Task { @MainActor in
            if let modelEntity = findModelEntity(by: payload.modelID) {
                // Reconstruct the simd_float4x4 from the array
                let transformMatrix = simd_float4x4.fromArray(payload.transform)
                modelEntity.transform.matrix = transformMatrix
                print("Applied transform to model with ID \(payload.modelID)")
            } else {
                print("Model entity with ID \(payload.modelID) not found")
            }
        }
    }

    func peerDidChangeState(peerID: MCPeerID, state: MCSessionState) {
        switch state {
        case .connected:
            if !connectedPeers.contains(peerID) {
                connectedPeers.append(peerID)
            }
            print("Connected to \(peerID.displayName)")
        case .notConnected:
            if let index = connectedPeers.firstIndex(of: peerID) {
                connectedPeers.remove(at: index)
            }
            print("Disconnected from \(peerID.displayName)")
        case .connecting:
            print("Connecting to \(peerID.displayName)")
        @unknown default:
            print("Unknown state for \(peerID.displayName)")
        }
    }

    func didReceiveInvitation(from peerID: MCPeerID, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("Accepting invitation from \(peerID.displayName)")
        invitationHandler(true, multipeerSession?.session)
    }
}

// MARK: - Helper Extensions and Structs

extension simd_float4x4 {
    func toArray() -> [Float] {
        let columns = [self.columns.0, self.columns.1, self.columns.2, self.columns.3]
        return columns.flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }

    static func fromArray(_ array: [Float]) -> simd_float4x4 {
        guard array.count == 16 else {
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

extension SIMD3 where Scalar == Float {
    var grounded: SIMD3<Float> {
        return SIMD3<Float>(x, 0, z) // Preserve x and z, but set y to 0
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        return SIMD3<Float>(x, y, z)
    }
}

extension ModelEntity {
    private struct AssociatedKeys {
        static var modelTypeKey: UInt8 = 0
    }

    func setModelType(_ modelType: ModelType) {
        objc_setAssociatedObject(self, &AssociatedKeys.modelTypeKey, modelType.rawValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    func getModelType() -> ModelType? {
        if let rawValue = objc_getAssociatedObject(self, &AssociatedKeys.modelTypeKey) as? String {
            return ModelType(rawValue: rawValue)
        }
        return nil
    }
}


// MARK: - Data Structures

struct ModelTransformPayload: Codable {
    let modelID: String
    let transform: [Float] // 16 elements representing the 4x4 matrix
}

struct SharedEntityData: Codable {
    let modelType: String
    let uniqueID: String
    let transform: TransformData
}

struct TransformData: Codable {
    let position: [Float]
    let orientation: [Float] // Quaternion [x, y, z, w]
    let scale: [Float]
}

enum DataType: UInt8 {
    case arWorldMap = 0
    case anchor = 1
    case collaborationData = 2
    case modelTransform = 3 // Match iOS value
}
