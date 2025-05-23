import Foundation
import RealityKit
import MultipeerConnectivity
import Combine // Needed for AnyCancellable if used later

#if os(iOS)
import ARKit
#endif

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
    /// Map from the persistent InstanceIDComponent.id to the corresponding Entity.ID
    private var instanceEntityMap: [String: Entity.ID] = [:]
    /// Reverse lookup: Map from instance ID to Entity for fast lookups
    private var instanceIDToEntity: [String: Entity] = [:]
    
        // Queue for handling received data
    private let receivingQueue = DispatchQueue(label: "com.xranatomy.receivingQueue")
    
        // MARK: - Initialization
    
        // Make modelManager non-optional in init
    init(multipeerSession: MultipeerSession, arViewModel: ARViewModel?, modelManager: ModelManager) {
        self.multipeerSession = multipeerSession
        self.arViewModel = arViewModel
        self.modelManager = modelManager // Assign the strong reference
        super.init()
        
        Logger.log("MyCustomConnectivityService initialized with ModelManager", category: .networking)
    }
    
        // MARK: - Entity Registration & Tracking
    
        /// Check if an entity is already registered
    func isEntityRegistered(_ entity: Entity) -> Bool {
        return entityLookup[entity.id] != nil
    }
    
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
            Logger.log("Assigned new InstanceID: \(instanceComp.id) to entity \(entityId)", category: .sync)
        } else if let existingComp = entity.components[InstanceIDComponent.self] {
            print("Entity \(entityId) already has InstanceID: \(existingComp.id)")
        } else {
            print("Error: Entity \(entityId) missing InstanceIDComponent unexpectedly.")
        }
        
        if let instanceComp = entity.components[InstanceIDComponent.self] {
            // Remember this mapping so we can dedupe and remove by instanceID later
            instanceEntityMap[instanceComp.id] = entity.id
            instanceIDToEntity[instanceComp.id] = entity
            Logger.log("Mapped instanceID \(instanceComp.id) to entityID \(entity.id)", category: .sync)
        }
        Logger.log("Registered entity: \(entityId) (locally owned: \(ownedByLocalPeer))", category: .sync)
    }
    
        /// Unregister an entity from the service
    func unregisterEntity(_ entity: Entity) {
        entityLookup.removeValue(forKey: entity.id)
        locallyOwnedEntities.remove(entity.id)
        
        // Clean up instance ID mappings
        if let instanceComp = entity.components[InstanceIDComponent.self] {
            instanceEntityMap.removeValue(forKey: instanceComp.id)
            instanceIDToEntity.removeValue(forKey: instanceComp.id)
        }
        
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
    func sendModelTransform(entity: Entity, modelType: ModelType? = nil, relativeToSharedAnchor: Bool = true) {
        guard multipeerSession.session.connectedPeers.count > 0 else { return }
        
        // Always get transform relative to shared image anchor
        let transformMatrix: simd_float4x4
        if let arViewModel = arViewModel {
            let sharedAnchor = arViewModel.sharedAnchorEntity
            if sharedAnchor.scene != nil {
                transformMatrix = entity.transformMatrix(relativeTo: sharedAnchor)
            } else {
                print("Warning: sharedAnchorEntity not ready. Cannot send transform.")
                return
            }
        } else {
            print("Error: ARViewModel not available. Cannot send transform.")
            return
        }
        
        let transformArray = transformMatrix.toArray()
        let modelTypeString = modelType?.rawValue
            // [L06] Use the InstanceIDComponent for a stable ID across sessions
        guard let instanceID = entity.components[InstanceIDComponent.self]?.id else {
            print("Error: Cannot send transform for entity \(entity.id) - missing InstanceIDComponent.")
            return
        }
        
        let payload = ModelTransformPayload(
            instanceID: instanceID,
            transform: transformArray,
            modelType: modelTypeString,
            isRelativeToSharedAnchor: true // Always relative to image anchor
        )
        
        do {
            let data = try JSONEncoder().encode(payload)
            multipeerSession.sendToAllPeers(data, dataType: .modelTransform)
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
            // Add case for ARWorldMap within iOS conditional compilation block
//            case .arWorldMap:
//                self.handleARWorldMap(payload, from: peerID)
#endif
            case .addModel:
                self.handleAddModel(payload, from: peerID)
            case .removeModel:
                self.handleRemoveModel(payload, from: peerID)
            case .testMessage:
                self.handleTestMessage(payload, from: peerID)
            default:
#if !os(iOS)
                    // Handle ARWorldMap case outside the #if os(iOS) block if needed,
                    // although it's primarily an iOS concept. Log if received on visionOS.
                if dataType == .arWorldMap {
                    print("Warning: Received ARWorldMap data on non-iOS platform from \(peerID.displayName). Ignoring.")
                } else {
                    print("Received unsupported data type: \(dataType)")
                }
#else
                    // If inside iOS block and still default, it's unsupported
                print("Received unsupported data type: \(dataType)")
#endif
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
            
            // [L02] suppress duplicate adds using instanceEntityMap
            if let existingEntityID = instanceEntityMap[instanceID] {
                print("Duplicate addModel suppressed: instanceID \(instanceID) already mapped to entityID \(existingEntityID)")
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
                            
                                // Always use image anchor as parent
                            guard let sharedAnchor = self.arViewModel?.sharedAnchorEntity else {
                                print("Error: sharedAnchorEntity not available. Cannot add model.")
                                return
                            }
                            
                            let targetParent: Entity = sharedAnchor
                            let transformToSet: simd_float4x4 = matrix // The transform received in the payload
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
                                // Check if anchor is ready
                                let sharedAnchorWorldTransform = sharedAnchor.transformMatrix(relativeTo: nil)
                                if sharedAnchorWorldTransform == matrix_identity_float4x4 && sharedAnchor.scene == nil {
                                    print("Error: SharedAnchorEntity is not ready. Cannot add received model \(payload.modelType) relative to it.")
                                    return
                                }
                                
                                // Apply the image-relative transform directly
                                modelEntity.transform.matrix = transformToSet
                                print("Applying received image-relative transform to \(payload.modelType) under sharedAnchorEntity.")
                            
                                // Add the model entity to the parent
                            targetParent.addChild(modelEntity)
                            print("Added received model \(payload.modelType) (InstanceID: \(instanceID)) to parent \(targetParent.name)")
                            
                            // Register the entity (owned by peer) - Ensure InstanceID is set first!
                            print("Registering received entity \(modelEntity.id) with InstanceID \(instanceID)")
                            self.registerEntity(modelEntity, modelType: modelType, ownedByLocalPeer: false)
                            
                            // Add to ModelManager's tracking
                            self.modelManager.modelDict[modelEntity] = model
                            self.modelManager.placedModels.append(model)
                            print("Added received model \(payload.modelType) (InstanceID: \(instanceID)) to ModelManager.")
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
            
            // [L02] Lookup the Entity.ID via our instanceEntityMap
            guard let entityID = instanceEntityMap[instanceID],
                  let entityToRemove = entityLookup[entityID] else {
                print("handleRemoveModel: No mapping found for instanceID \(instanceID). Known IDs: \(Array(instanceEntityMap.keys))")
                return
            }
            print("handleRemoveModel: Found entity \(entityToRemove.name) (ID: \(entityToRemove.id)) matching InstanceID \(instanceID).")
            
                // Remove using ModelManager on the main thread
            DispatchQueue.main.async { [weak self] in
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
                instanceEntityMap.removeValue(forKey: instanceID)
                print("handleRemoveModel: Removed mapping for instanceID \(instanceID)")
                }
            }
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
            DispatchQueue.main.async { [weak self] in
                self?.arViewModel?.alertItem = AlertItem(title: "Test Message Received", message: "From \(payload.senderName): \(payload.message)")
            }
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
            
                // Process on main thread for scene graph manipulation
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                    // [L02] Find the entity by instanceID using reverse lookup
                guard let entity = self.instanceIDToEntity[instanceID] else {
                    print("handleModelTransform: Could not find entity with instanceID \(instanceID).")
                    return
                }
                    // print("handleModelTransform: Found entity \(entity.name) (ID: \(instanceID)) to update.") // Reduce log noise
                
                guard let arViewModel = self.arViewModel else {
                    print("ARViewModel not found, cannot update transform for \(instanceID)")
                    return
                }
                
                // Always use sharedAnchorEntity as parent
                let sharedAnchorWorldTransform = arViewModel.sharedAnchorEntity.transformMatrix(relativeTo: nil)
                if sharedAnchorWorldTransform == matrix_identity_float4x4 && arViewModel.sharedAnchorEntity.scene == nil {
                    print("Warning: sharedAnchorEntity not ready. Skipping transform update for \(instanceID).")
                    return
                }
                
                    // Ensure entity is parented to sharedAnchorEntity
                let currentParent = entity.parent
                if currentParent !== arViewModel.sharedAnchorEntity {
                    entity.setParent(arViewModel.sharedAnchorEntity, preservingWorldTransform: false)
                    print("Reparented \(instanceID) to sharedAnchorEntity.")
                }
                
                
                    // Apply the image-relative transform
                    let sharedAnchor = arViewModel.sharedAnchorEntity
                    guard sharedAnchor.scene != nil else {
                        print("Warning: Shared anchor not ready. Skipping transform for \(instanceID).")
                        return
                    }
                    
                    // Transform is always relative to shared anchor
                    entity.setTransformMatrix(matrix, relativeTo: sharedAnchor)
                
                    // Update the LastTransformComponent cache *after* applying
                entity.components[LastTransformComponent.self] = LastTransformComponent(matrix: entity.transform.matrix)
                
                    // print("Applied transform to \(instanceID). Receiver Mode: \(currentSyncMode.rawValue), Received Relative: \(isReceivedTransformRelative)") // Reduce log noise
            } // End of DispatchQueue.main.async block
        } // End of handleModelTransform function
    }
}
