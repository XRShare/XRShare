import Foundation
import RealityKit
import MultipeerConnectivity
import Combine // Needed for AnyCancellable if used later

#if os(iOS)
import ARKit
#endif
import GroupActivities

// MARK: - Custom PeerID
public final class CustomPeerID: SynchronizationPeerID, Hashable {
    private let uuid = UUID()
    
    public static func == (lhs: CustomPeerID, rhs: CustomPeerID) -> Bool {
        lhs.uuid == rhs.uuid
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }
}

// MARK: - UUID Conversion Methods
extension Entity.ID {
    var stringValue: String {
        // A more robust way to get a consistent string representation
        return String(self.hashValue)
    }
}

// Add instance ID component
struct InstanceIDComponent: Component, Codable {
    var id: String = UUID().uuidString // Assign unique ID on creation
}

// MARK: - MyCustomConnectivityService
/// A custom connectivity service for RealityKit scene synchronization
class MyCustomConnectivityService: NSObject {
    // MARK: - Properties
    /// The underlying multipeer connectivity session
    var multipeerSession: MultipeerSession
    weak var arViewModel: ARViewModel? // Keep weak ref to avoid retain cycles if ARViewModel owns this service
    var modelManager: ModelManager // Change to strong reference
    
    // Entity tracking (make accessible for sync logic)
    var entityLookup: [Entity.ID: Entity] = [:]
    var locallyOwnedEntities: Set<Entity.ID> = []
    
    // Queue for handling received data
    private let receivingQueue = DispatchQueue(label: "com.xranatomy.receivingQueue")
    
    // MARK: - Initialization
    
    // Make modelManager non-optional in init
    init(multipeerSession: MultipeerSession, arViewModel: ARViewModel?, modelManager: ModelManager) {
        self.multipeerSession = multipeerSession
        self.arViewModel = arViewModel
        self.modelManager = modelManager // Assign the strong reference
        super.init()
        
        print("MyCustomConnectivityService initialized with ModelManager")
    }
    
    // MARK: - Entity Registration & Tracking
    
    /// Register an entity with the service for synchronization
    func registerEntity(_ entity: Entity, modelType: ModelType? = nil, ownedByLocalPeer: Bool = true) {
        let entityId = entity.id
        entityLookup[entityId] = entity
        
        if ownedByLocalPeer {
            locallyOwnedEntities.insert(entityId)
            
            // If this is an anchor entity, mark all its children as locally owned too
            if entity is AnchorEntity {
                for child in entity.children {
                    locallyOwnedEntities.insert(child.id)
                    entityLookup[child.id] = child
                }
            }
        }
        
        // Add model type component if available
        if let modelType = modelType, entity is ModelEntity {
            entity.components[ModelTypeComponent.self] = ModelTypeComponent(type: modelType)
        }
        
        // Add or retrieve instance ID
        if entity.components[InstanceIDComponent.self] == nil {
             let instanceComp = InstanceIDComponent()
             entity.components[InstanceIDComponent.self] = instanceComp
             print("Assigned new InstanceID: \(instanceComp.id) to entity \(entityId)")
        } else {
             print("Entity \(entityId) already has InstanceID: \(entity.components[InstanceIDComponent.self]!.id)")
        }
        
        print("Registered entity: \(entityId) (locally owned: \(ownedByLocalPeer))")
    }
    
    /// Unregister an entity from the service
    func unregisterEntity(_ entity: Entity) {
        entityLookup.removeValue(forKey: entity.id)
        locallyOwnedEntities.remove(entity.id)
        
        // If this is an anchor entity, unregister all its children too
        if entity is AnchorEntity {
            for child in entity.children {
                entityLookup.removeValue(forKey: child.id)
                locallyOwnedEntities.remove(child.id)
            }
        }
        
        print("Unregistered entity: \(entity.id)")
    }
    
    // MARK: - Data Sending Methods
    
    /// Send model transform to all peers
    // Renamed flag for clarity
    func sendModelTransform(entity: Entity, modelType: ModelType? = nil, relativeToSharedAnchor: Bool = false) {
        guard multipeerSession.session.connectedPeers.count > 0 else { return }

        // Get the appropriate transform based on the flag
        let transformMatrix: simd_float4x4
        if relativeToSharedAnchor, let arViewModel = arViewModel,
           (arViewModel.currentSyncMode == .imageTarget || arViewModel.currentSyncMode == .objectTarget) {
            // Image/Object Target Mode: send transform relative to shared anchor
            let sharedAnchor = arViewModel.sharedAnchorEntity
            if sharedAnchor.scene != nil {
                transformMatrix = entity.transformMatrix(relativeTo: sharedAnchor)
            } else {
                print("Warning: sharedAnchorEntity not ready. Sending world transform instead.")
                transformMatrix = entity.transformMatrix(relativeTo: nil)
            }
        } else {
            // World Mode: send world transform directly
            transformMatrix = entity.transformMatrix(relativeTo: nil)
        }

        let transformArray = transformMatrix.toArray()
        let modelTypeString = modelType?.rawValue
        // [L06] Use the InstanceIDComponent for a stable ID across sessions
        guard let instanceID = entity.components[InstanceIDComponent.self]?.id else {
            print("Error: Cannot send transform for entity \(entity.id) - missing InstanceIDComponent.")
            return
        }

        let payload = ModelTransformPayload(
            instanceID: instanceID, // Use instanceID here
            transform: transformArray,
            modelType: modelTypeString,
            isRelativeToSharedAnchor: relativeToSharedAnchor // Use the generic flag name here
        )

        do {
            let data = try JSONEncoder().encode(payload)
            multipeerSession.sendToAllPeers(data, dataType: .modelTransform)
            // Also broadcast via SharePlay if available
            if let messenger = SharePlaySyncController.shared.messenger {
                Task {
                    do {
                        try await messenger.send(payload, to: .all)
                    } catch {
                        print("SharePlay: failed to send modelTransform: \(error)")
                    }
                }
            }
        } catch {
            print("Error encoding model transform: \(error)")
        }
    }
    
    /// Broadcast creation of an anchor with optional model
    func broadcastAnchorCreation(_ anchor: AnchorEntity, modelType: ModelType? = nil) {
        guard multipeerSession.session.connectedPeers.count > 0 else { return }

        // Get all ModelEntity children
        let modelEntities = anchor.children.compactMap { $0 as? ModelEntity }
        guard !modelEntities.isEmpty || modelType != nil else {
            print("Warning: Trying to broadcast anchor without model entities or model type")
            return
        }

        let anchorTransform = anchor.transform.matrix.toArray()
        let anchorID = "anchor-\(anchor.id.stringValue)" // Use anchorID
        let modelTypeString = modelType?.rawValue ?? modelEntities.first?.components[ModelTypeComponent.self]?.type.rawValue

        // Use empty Data if no ARKit anchor
        let anchorData = Data()

        let payload = AnchorTransformPayload(
            anchorData: anchorData,
            anchorID: anchorID, // Use anchorID field
            transform: anchorTransform,
            modelType: modelTypeString
        )

        do {
            let data = try JSONEncoder().encode(payload)
            multipeerSession.sendToAllPeers(data, dataType: .anchorWithTransform)
            print("Broadcast anchor creation with model type: \(modelTypeString ?? "unknown")")
        } catch {
            print("Error encoding anchor creation: \(error)")
        }
    }
    
    #if os(iOS)
    /// Broadcast ARKit anchor removal
    func broadcastAnchorRemoval(_ anchor: ARAnchor) {
        guard multipeerSession.session.connectedPeers.count > 0 else { return }
        
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: anchor.identifier.uuidString, requiringSecureCoding: true)
            multipeerSession.sendToAllPeers(data, dataType: .removeAnchors)
            print("Broadcast anchor removal: \(anchor.identifier)")
        } catch {
            print("Error encoding anchor removal: \(error)")
        }
    }
    #endif
    
    // MARK: - Data Receiving Methods
    
    /// Handle incoming multipeer data
    func handleReceivedData(_ data: Data, from peerID: MCPeerID) {
        // Process received data on a background queue
        receivingQueue.async {
            guard data.count > 0, let dataType = DataType(rawValue: data[0]) else {
                print("Invalid data received")
                return
            }
            
            let payload = data.subdata(in: 1..<data.count)
            
            // Handle based on data type
            switch dataType {
            case .modelTransform:
                do {
                    try self.handleModelTransform(payload, from: peerID)
                } catch {
                    print("Error in handleModelTransform: \(error)")
                }
            case .anchorWithTransform:
                self.handleAnchorWithTransform(payload, from: peerID)
            #if os(iOS) // Wrap iOS specific handlers
//            case .collaborationData:
//                self.handleCollaborationData(payload, from: peerID)
//            case .removeAnchors:
//                self.handleRemoveAnchors(payload, from: peerID)
            #endif
            case .addModel:
                self.handleAddModel(payload, from: peerID)
            case .removeModel:
                self.handleRemoveModel(payload, from: peerID)
            case .testMessage:
                self.handleTestMessage(payload, from: peerID)
            default:
                print("Received unsupported data type: \(dataType)")
            }
        }
    }
    
    // MARK: - Add/Remove Model Handlers

    private func handleAddModel(_ data: Data, from peerID: MCPeerID) {
        do {
            let payload = try JSONDecoder().decode(AddModelPayload.self, from: data)
            print("Received addModel: \(payload.modelType) (ID: \(payload.instanceID)) from \(peerID.displayName), Relative: \(payload.isRelativeToSharedAnchor)")

            let modelType = ModelType(rawValue: payload.modelType)
            let instanceID = payload.instanceID // [L06] Use instanceID from payload
            let matrix = simd_float4x4.fromArray(payload.transform)
            let isReceivedTransformRelative = payload.isRelativeToSharedAnchor // Flag from sender

            // [L02] Check if model with this instance ID already exists using InstanceIDComponent
            if entityLookup.values.contains(where: { $0.components[InstanceIDComponent.self]?.id == instanceID }) {
                print("Model with instance ID \(instanceID) already exists. Ignoring addModel.")
                return
            }

            // Load the model on the main thread
            DispatchQueue.main.async(execute: DispatchWorkItem(block: {
                Task {
                    // Load model (simplified loading logic for brevity)
                    let model = await Model.load(modelType: modelType, arViewModel: self.arViewModel)

                    if let modelEntity = await model.modelEntity {
                        await MainActor.run {
                            // [L06] Assign the received instance ID
                            modelEntity.components[InstanceIDComponent.self] = InstanceIDComponent(id: instanceID)

                            // [L02 & L03] Determine the target parent and add the entity based on CURRENT sync mode
                            let targetParent: Entity?
                            let transformToSet: simd_float4x4 = matrix // The transform received in the payload
                            let currentSyncMode = self.arViewModel?.currentSyncMode ?? .world // Get receiver's current sync mode

                            // Check if the receiver is in a relative mode (Image or Object)
                            if (currentSyncMode == .imageTarget || currentSyncMode == .objectTarget), let sharedAnchor = self.arViewModel?.sharedAnchorEntity {
                                // --- Receiver is in Image or Object Target Mode ---
                                targetParent = sharedAnchor
                                // [L03] Ensure shared anchor is in the scene graph before parenting
                                #if os(iOS)
                                if sharedAnchor.scene == nil, let scene = self.arViewModel?.currentScene {
                                     if scene.anchors.first(where: { $0 == sharedAnchor }) == nil {
                                         scene.addAnchor(sharedAnchor)
                                         print("Added sharedAnchorEntity to scene in handleAddModel (iOS).")
                                     }
                                }
                                #elseif os(visionOS)
                                // On visionOS, RealityView manages adding anchors from the content.
                                // We still need to check if it's ready (has transform or is in scene).
                                #endif
                                // Check if anchor is ready (has non-identity transform or is in scene)
                                let sharedAnchorWorldTransform = sharedAnchor.transformMatrix(relativeTo: nil)
                                if sharedAnchorWorldTransform == matrix_identity_float4x4 && sharedAnchor.scene == nil {
                                     print("Error: SharedAnchorEntity is not ready. Cannot add received model \(payload.modelType) relative to it.")
                                     return // Skip adding the model
                                }

                                // Apply transform: If received transform was relative, apply directly. If world, convert to relative.
                                if isReceivedTransformRelative {
                                    modelEntity.transform.matrix = transformToSet // Apply directly
                                    print("Applying received relative transform to \(payload.modelType) under sharedAnchorEntity.")
                                } else {
                                    // Convert received world transform to be relative to shared anchor
                                    let relativeMatrix = transformToSet * sharedAnchorWorldTransform.inverse
                                    modelEntity.transform.matrix = relativeMatrix
                                    print("Converting received world transform to relative for \(payload.modelType) under sharedAnchorEntity.")
                                }

                            } else {
                                // --- Receiver is in World Mode ---
                                if isReceivedTransformRelative {
                                     print("Warning: Received relative transform flag for \(payload.modelType) but receiver is in World mode. Applying as world transform.")
                                }
                                #if os(iOS)
                                // On iOS, create a new AnchorEntity at the received world transform and add the model to it.
                                let worldAnchor = AnchorEntity(world: transformToSet) // Use received world transform
                                targetParent = worldAnchor
                                if let scene = self.arViewModel?.currentScene {
                                    scene.addAnchor(worldAnchor)
                                    print("Added new world AnchorEntity to scene for received model \(payload.modelType) (iOS).")
                                    modelEntity.transform = Transform() // Model's local transform relative to its anchor is identity
                                } else {
                                     print("Warning: No scene found, cannot add world anchor for \(payload.modelType) (iOS).")
                                     return
                                }
                                #elseif os(visionOS)
                                // On visionOS, parent under the predefined 'modelAnchor'.
                                if let scene = self.arViewModel?.currentScene,
                                   let modelAnchor = scene.findEntity(named: "modelAnchor") as? AnchorEntity {
                                    targetParent = modelAnchor
                                    // [L03] Ensure modelAnchor is in the scene graph
                                    if modelAnchor.scene == nil {
                                        print("Error: modelAnchor not found in visionOS scene graph. Cannot place received model \(payload.modelType).")
                                        return // Skip adding
                                    }
                                    print("Target parent for \(payload.modelType) is modelAnchor (visionOS).")
                                    // Apply the received world transform relative to nil (entity will be added to modelAnchor below)
                                    modelEntity.setTransformMatrix(transformToSet, relativeTo: nil)
                                } else {
                                    print("Warning: modelAnchor not found in visionOS scene. Cannot place received model \(payload.modelType).")
                                    targetParent = nil // Indicate failure
                                }
                                #else
                                targetParent = nil // Fallback
                                #endif
                            }

                            // Add the model entity to the determined parent if found
                            if let parent = targetParent {
                                parent.addChild(modelEntity)
                                print("Added received model \(payload.modelType) (InstanceID: \(instanceID)) to parent \(parent.name). Receiver Mode: \(currentSyncMode.rawValue)")

                                // Register the entity (owned by peer) - Ensure InstanceID is set first!
                                print("Registering received entity \(modelEntity.id) with InstanceID \(instanceID)")
                                self.registerEntity(modelEntity, modelType: modelType, ownedByLocalPeer: false)

                                // Add to ModelManager's tracking
                                self.modelManager.modelDict[modelEntity] = model
                                self.modelManager.placedModels.append(model)
                                print("Added received model \(payload.modelType) (InstanceID: \(instanceID)) to ModelManager.")

                            } else {
                                print("Failed to add received model \(payload.modelType) because a suitable parent could not be determined or added.")
                            }
                        }
                    } else {
                        print("Failed to load model entity for received model: \(payload.modelType)")
                    }
                }
            }))
        } catch {
            print("Error decoding AddModelPayload: \(error)")
        }
    }

    private func handleRemoveModel(_ data: Data, from peerID: MCPeerID) {
        do {
            let payload = try JSONDecoder().decode(RemoveModelPayload.self, from: data)
            let instanceID = payload.instanceID // [L06] Use instanceID from payload
            print("Received removeModel request for InstanceID: \(instanceID) from \(peerID.displayName)")

            // [L02] Find the entity with this instance ID in the lookup using InstanceIDComponent
            guard let entityToRemove = entityLookup.values.first(where: { $0.components[InstanceIDComponent.self]?.id == instanceID }) else {
                print("handleRemoveModel: Could not find entity with instance ID \(instanceID) in local entityLookup.")
                // Log current lookup for debugging
                let currentIDs = entityLookup.values.compactMap { $0.components[InstanceIDComponent.self]?.id }
                print("handleRemoveModel: Current known instance IDs: \(currentIDs)")
                return
            }
            print("handleRemoveModel: Found entity \(entityToRemove.name) (ID: \(entityToRemove.id)) matching InstanceID \(instanceID).")

            // Remove using ModelManager on the main thread
            DispatchQueue.main.async(execute: DispatchWorkItem(block: { [weak self] in // Use weak self
                guard let self = self else { return }

                // Double-check if the entity still exists before removal attempt
                guard let currentEntity = self.entityLookup[entityToRemove.id] else {
                    print("handleRemoveModel: Entity \(entityToRemove.name) (InstanceID: \(instanceID)) disappeared before removal could be executed on main thread.")
                    return
                }

                // Find the corresponding Model instance in ModelManager using the entity
                let model = self.modelManager.modelDict[currentEntity]
                if let model = model {
                    print("handleRemoveModel: Found model \(model.modelType.rawValue) in ModelManager for InstanceID \(instanceID). Calling removeModel(broadcast: false).")
                    // Call removeModel with broadcast: false to prevent loop
                    Task { @MainActor in
                        // Pass the specific model instance found
                        self.modelManager.removeModel(model, broadcast: false) // removeModel should handle unregistration
                        print("handleRemoveModel: Successfully called modelManager.removeModel for \(model.modelType.rawValue) (InstanceID: \(instanceID))")
                    }

                } else {
                    // Fallback if not found in ModelManager (shouldn't happen ideally)
                    print("handleRemoveModel Warning: Model for InstanceID \(instanceID) not found in ModelManager dictionary. Removing entity \(currentEntity.name) directly from parent and unregistering.")
                    currentEntity.removeFromParent()
                    self.unregisterEntity(currentEntity) // Ensure unregistration in fallback
                }
            }))
        } catch {
            print("Error decoding RemoveModelPayload: \(error)")
        }
    }
    
    // MARK: - Test Message Handler
    
    private func handleTestMessage(_ data: Data, from peerID: MCPeerID) {
        do {
            let payload = try JSONDecoder().decode(TestMessagePayload.self, from: data)
            print("✅ Received Test Message from \(payload.senderName): \"\(payload.message)\"")
            // Optionally, display an alert or update UI via ARViewModel
            DispatchQueue.main.async(execute: DispatchWorkItem(block: {
                 self.arViewModel?.alertItem = AlertItem(title: "Test Message Received", message: "From \(payload.senderName): \(payload.message)")
            }))
        } catch {
            print("Error decoding TestMessagePayload: \(error)")
        }
    }
    
    // MARK: - Internal helper methods

    func handleAnchorWithTransform(_ data: Data, from peerID: MCPeerID) {
        do {
            let payload = try JSONDecoder().decode(AnchorTransformPayload.self, from: data)
            print("handleAnchorWithTransform: anchorID=\(payload.anchorID)") // Use anchorID

            let matrix = simd_float4x4.fromArray(payload.transform)
            let anchor = AnchorEntity()
            anchor.transform.matrix = matrix

            // If we have a model type, load and attach the model
            if let modelTypeStr = payload.modelType {
                let modelType = ModelType(rawValue: modelTypeStr)

                // On the main thread, attempt to load and place the model
                DispatchQueue.main.async {
                    Task {
                        // First check if we already have this model loaded in our arViewModel
                        if let arViewModel = self.arViewModel,
                           let existingModel = arViewModel.models.first(where: { $0.modelType.rawValue.lowercased() == modelTypeStr.lowercased() }),
                           let modelEntity = existingModel.modelEntity?.clone(recursive: true) {

                            // Use the existing model
                            anchor.addChild(modelEntity)

                            // Register entities
                            self.registerEntity(anchor, ownedByLocalPeer: false)
                            // Ensure the cloned entity gets a unique instance ID if needed, or reuse if appropriate
                            if modelEntity.components[InstanceIDComponent.self] == nil {
                                modelEntity.components.set(InstanceIDComponent())
                            }
                            self.registerEntity(modelEntity, modelType: existingModel.modelType, ownedByLocalPeer: false)

                            // Add to scene
                            if let scene = self.arViewModel?.currentScene {
                                #if os(iOS)
                                scene.addAnchor(anchor)
                                #elseif os(visionOS)
                                // For visionOS, manual anchor addition is not supported; no action taken
                                #endif
                            }

                            print("Added anchor from peer using existing model")
                        } else {
                            // Otherwise load the model
                            let model = await Model.load(modelType: modelType)

                            if let modelEntity = model.modelEntity {
                                await MainActor.run {
                                    anchor.addChild(modelEntity)

                                    // Register entities
                                    self.registerEntity(anchor, ownedByLocalPeer: false)
                                    // Ensure the new entity gets an instance ID
                                    if modelEntity.components[InstanceIDComponent.self] == nil {
                                        modelEntity.components.set(InstanceIDComponent())
                                    }
                                    self.registerEntity(modelEntity, modelType: modelType, ownedByLocalPeer: false)

                                    // Add to scene
                                    if let scene = self.arViewModel?.currentScene {
                                        #if os(iOS)
                                        scene.addAnchor(anchor)
                                        #elseif os(visionOS)
                                        // For visionOS, manual anchor addition is not supported; no action taken
                                        #endif
                                    }

                                    // Add to model manager
                                    self.modelManager.modelDict[modelEntity] = model
                                    self.modelManager.placedModels.append(model)

                                    print("Added anchor from peer with newly loaded model")
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            print("Error decoding AnchorTransformPayload: \(error)")
        }
    }
    
    func handleModelTransform(_ data: Data, from peerID: MCPeerID) throws {
        do {
            let payload = try JSONDecoder().decode(ModelTransformPayload.self, from: data)
            let instanceID = payload.instanceID // [L06] Use instanceID from payload
            let matrix = simd_float4x4.fromArray(payload.transform)
            let isReceivedTransformRelative = payload.isRelativeToSharedAnchor // Flag from sender

            // Process on main thread for scene graph manipulation
            DispatchQueue.main.async(execute: DispatchWorkItem(block: {
                // [L02] Find the entity by instanceID
                guard let entity = self.entityLookup.values.first(where: { $0.components[InstanceIDComponent.self]?.id == instanceID }) else {
                    print("handleModelTransform: Could not find entity with instanceID \(instanceID).")
                    return
                }
                // print("handleModelTransform: Found entity \(entity.name) (ID: \(instanceID)) to update.") // Reduce log noise

                guard let arViewModel = self.arViewModel else {
                    print("ARViewModel not found, cannot update transform for \(instanceID)")
                    return
                }

                // [L02 & L03] Determine the expected parent based on the receiver's current sync mode
                let currentSyncMode = arViewModel.currentSyncMode
                let intendedParent: Entity?
                let intendedParentName: String

                if currentSyncMode == .imageTarget || currentSyncMode == .objectTarget {
                    // --- Receiver is in Image or Object Target Mode ---
                    intendedParent = arViewModel.sharedAnchorEntity
                    intendedParentName = "sharedAnchorEntity (\(currentSyncMode.rawValue))"
                    // [L03] Check if shared anchor is ready
                    let sharedAnchorWorldTransform = arViewModel.sharedAnchorEntity.transformMatrix(relativeTo: nil)
                    if sharedAnchorWorldTransform == matrix_identity_float4x4 && arViewModel.sharedAnchorEntity.scene == nil {
                         print("Warning: Expected parent (\(intendedParentName)) for relative transform is not ready. Skipping transform update for \(instanceID).")
                         return
                    }
                } else {
                    // --- Receiver is in World Mode ---
                    #if os(iOS)
                    // On iOS, the parent should be a world AnchorEntity. Find it or assume scene root.
                    // For simplicity, we'll assume the transform is world and apply directly.
                    // Reparenting logic below handles moving it if needed.
                    intendedParent = entity.parent as? AnchorEntity // Check if already under a world anchor
                    intendedParentName = "World Anchor (iOS)"
                    #elseif os(visionOS)
                    // On visionOS, the parent should be modelAnchor.
                    if let scene = arViewModel.currentScene, let modelAnchor = scene.findEntity(named: "modelAnchor") as? AnchorEntity {
                        intendedParent = modelAnchor
                        intendedParentName = "modelAnchor (visionOS)"
                        // [L03] Check if modelAnchor is ready
                        if modelAnchor.scene == nil {
                            print("Warning: Expected parent (\(intendedParentName)) for world transform is not ready. Skipping transform update for \(instanceID).")
                            return
                        }
                    } else {
                        print("Warning: modelAnchor not found in visionOS scene. Cannot determine intended parent for \(instanceID). Skipping update.")
                        return
                    }
                    #else
                    intendedParent = nil // Fallback
                    intendedParentName = "Unknown World Parent"
                    #endif
                }

                // --- Reparenting Logic ---
                let currentParent = entity.parent
                var needsReparenting = false

                if (currentSyncMode == .imageTarget || currentSyncMode == .objectTarget) {
                    if currentParent !== intendedParent { // Intended parent is sharedAnchorEntity
                        needsReparenting = true
                        print("Reparenting \(instanceID) to \(intendedParentName).")
                    }
                } else { // World Mode
                    #if os(iOS)
                    // In world mode, parent should NOT be sharedAnchorEntity.
                    if currentParent === arViewModel.sharedAnchorEntity {
                        needsReparenting = true
                        print("Reparenting \(instanceID) from sharedAnchorEntity to World (iOS).")
                        // On iOS, when reparenting to world, create a new anchor at the entity's current world pos
                        let newWorldAnchor = AnchorEntity(world: entity.transformMatrix(relativeTo: nil))
                        if let scene = arViewModel.currentScene {
                            scene.addAnchor(newWorldAnchor)
                            entity.setParent(newWorldAnchor, preservingWorldTransform: true)
                            entity.transform = Transform() // Reset local transform relative to new anchor
                            print("Successfully reparented \(instanceID) to new World Anchor (iOS).")
                        } else {
                            print("Error: Cannot reparent \(instanceID) to World (iOS) - scene not found.")
                            return // Skip update if scene is missing
                        }
                        needsReparenting = false // Handled reparenting here
                    }
                    // We don't strictly enforce parenting under a specific world anchor here,
                    // as long as it's not the shared one.
                    #elseif os(visionOS)
                    // In world mode, parent SHOULD be modelAnchor.
                    if currentParent !== intendedParent { // Intended parent is modelAnchor
                        needsReparenting = true
                        print("Reparenting \(instanceID) to \(intendedParentName).")
                    }
                    #endif
                }

                if needsReparenting {
                    guard let validIntendedParent = intendedParent else {
                        print("Error: Cannot reparent \(instanceID) - intended parent is nil.")
                        return // Skip update if intended parent is invalid
                    }
                    // Preserve world transform during reparenting
                    entity.setParent(validIntendedParent, preservingWorldTransform: true)
                    print("Successfully reparented \(instanceID) to \(validIntendedParent.name).")
                }
                // --- End Reparenting ---


                // --- Apply Transform Logic ---
                // Apply transform AFTER potential reparenting
                if currentSyncMode == .imageTarget || currentSyncMode == .objectTarget {
                    // Image/Object Target Mode: apply transform relative to shared anchor
                    let sharedAnchor = arViewModel.sharedAnchorEntity
                    // Ensure shared anchor is in the scene graph
                    guard sharedAnchor.scene != nil else {
                        print("Warning: Shared anchor not ready. Skipping transform for \(instanceID).")
                        return
                    }
                    if isReceivedTransformRelative {
                        // Received transform is relative to shared anchor
                        entity.setTransformMatrix(matrix, relativeTo: sharedAnchor)
                    } else {
                        // Received world transform: convert to relative
                        let anchorWorld = sharedAnchor.transformMatrix(relativeTo: nil)
                        let relativeMatrix = anchorWorld.inverse * matrix
                        entity.setTransformMatrix(relativeMatrix, relativeTo: sharedAnchor)
                        print("Converted received world transform to relative for \(instanceID) under \(intendedParentName).")
                    }
                } else {
                    // World Mode: apply world transform directly
                    if isReceivedTransformRelative {
                        print("Warning: Received relative transform for \(instanceID) but in World mode. Applying as world transform.")
                    }
                    entity.setTransformMatrix(matrix, relativeTo: nil)
                }
                // --- End Apply Transform ---

                // Update the LastTransformComponent cache *after* applying
                entity.components[LastTransformComponent.self] = LastTransformComponent(matrix: entity.transform.matrix)

                // print("Applied transform to \(instanceID). Receiver Mode: \(currentSyncMode.rawValue), Received Relative: \(isReceivedTransformRelative)") // Reduce log noise
            })) // End of DispatchQueue.main.async block
    } // End of handleModelTransform function

    #if os(iOS) // Wrap the entire function definition
    func handleCollaborationData(_ data: Data, from peerID: MCPeerID) {
        guard let arView = arViewModel?.arView else { return }

        do {
            if let collaborationData = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: ARSession.CollaborationData.self,
                from: data) {

                arView.session.update(with: collaborationData)
            }
        } catch {
            print("Error decoding collaboration data: \(error)")
        }
    }
    #endif // End of handleCollaborationData wrapper

    #if os(iOS) // Wrap the entire function definition
    func handleRemoveAnchors(_ data: Data, from peerID: MCPeerID) {
        guard let arView = arViewModel?.arView else { return }

        do {
            if let uuidString = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSString.self,
                from: data) as String?,
               let uuid = UUID(uuidString: uuidString) {

                // Find and remove the anchor
                if let anchor = arView.session.currentFrame?.anchors.first(where: { $0.identifier == uuid }) {
                    arView.session.remove(anchor: anchor)
                    print("Removed anchor: \(uuid)")
                }

                // Remove from arViewModel's tracked anchors
                if let index = arViewModel?.placedAnchors.firstIndex(where: { $0.identifier == uuid }) {
                    arViewModel?.placedAnchors.remove(at: index)
                }
            }
        } catch {
            print("Error decoding anchor removal data: \(error)")
        }
    }
    #endif // End of handleRemoveAnchors wrapper

    // Helper method removed as fallback logic is removed.
    // private func applyTransformToFallbackEntity(entity: Entity, matrix: simd_float4x4, isRelative: Bool) { ... }
} // End of MyCustomConnectivityService class - Ensure this brace is correctly placed and matches the class opening.
}
