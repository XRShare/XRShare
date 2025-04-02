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
    private var multipeerSession: MultipeerSession
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
        if relativeToSharedAnchor, let arViewModel = arViewModel, (arViewModel.currentSyncMode == .imageTarget || arViewModel.currentSyncMode == .objectTarget) {
            // --- Image or Object Target Mode ---
            // Calculate the transform relative to the shared anchor entity.
            // Ensure sharedAnchorEntity is valid before calculating relative transform.
            // Check if sharedAnchorEntity has a valid transform in the world.
            let sharedAnchorWorldTransform = arViewModel.sharedAnchorEntity.transformMatrix(relativeTo: nil)
            if sharedAnchorWorldTransform != matrix_identity_float4x4 || arViewModel.sharedAnchorEntity.scene != nil {
                // Calculate relative transform: entityWorld * inverse(anchorWorld)
                let entityWorldTransform = entity.transformMatrix(relativeTo: nil)
                transformMatrix = entityWorldTransform * sharedAnchorWorldTransform.inverse
                print("Sending transform relative to shared anchor.")
            } else {
                print("Warning: sharedAnchorEntity not ready for relative transform calculation (transform is identity or not in scene). Sending world transform instead.")
                transformMatrix = entity.transformMatrix(relativeTo: nil) // Fallback to world
            }
        } else {
            // --- World Mode ---
            // Use the world transform (transform relative to nil).
            transformMatrix = entity.transformMatrix(relativeTo: nil)
            print("Sending world transform.")
        }

        let transformArray = transformMatrix.toArray()
        let modelTypeString = modelType?.rawValue
        // Use the InstanceIDComponent for a stable ID across sessions
        let instanceID = entity.components[InstanceIDComponent.self]?.id ?? entity.id.stringValue

        let payload = ModelTransformPayload(
            modelID: instanceID, // Use instanceID here
            transform: transformArray,
            modelType: modelTypeString,
            isRelativeToImageAnchor: relativeToSharedAnchor // Use the generic flag name here
        )

        do {
            let data = try JSONEncoder().encode(payload)
            multipeerSession.sendToAllPeers(data, dataType: .modelTransform)
            
            // Debug messages slowing things down? Comment out or limit frequency.
            // print("Sent model transform: \(modelID)")
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
        let modelID = "anchor-\(anchor.id.stringValue)"
        let modelTypeString = modelType?.rawValue ?? modelEntities.first?.components[ModelTypeComponent.self]?.type.rawValue
        
        // Use empty Data if no ARKit anchor
        let anchorData = Data()
        
        let payload = AnchorTransformPayload(
            anchorData: anchorData,
            modelID: modelID,
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
            case .collaborationData:
                #if os(iOS)
                self.handleCollaborationData(payload, from: peerID)
                #endif
            case .removeAnchors:
                #if os(iOS)
                self.handleRemoveAnchors(payload, from: peerID)
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
            print("Received addModel: \(payload.modelType) (ID: \(payload.instanceID)) from \(peerID.displayName)")
            
            let modelType = ModelType(rawValue: payload.modelType)
            let instanceID = payload.instanceID
            let matrix = simd_float4x4.fromArray(payload.transform)
            let isRelativeToImageAnchor = payload.isRelativeToImageAnchor
            
            // Check if model with this instance ID already exists
            if entityLookup.values.contains(where: { $0.components[InstanceIDComponent.self]?.id == instanceID }) {
                print("Model with instance ID \(instanceID) already exists. Ignoring addModel.")
                return
            }

            // Load the model on the main thread
            DispatchQueue.main.async(execute: DispatchWorkItem(block: {
                Task {
                    // Check if the ModelManager has a *template* model of this type loaded
                    let existingModelTemplate = self.modelManager.modelTypes.first(where: { $0.rawValue == payload.modelType }) != nil
                    
                    let model: Model
                    if existingModelTemplate {
                         // If template exists, create a new Model instance but try to reuse loaded entity data if possible
                         // This part needs careful handling - for now, just load fresh
                         model = await Model.load(modelType: modelType, arViewModel: self.arViewModel)
                    } else {
                         // Load fresh if no template or manager
                         model = await Model.load(modelType: modelType, arViewModel: self.arViewModel)
                    }

                    if let modelEntity = await model.modelEntity {
                        await MainActor.run {
                            // Assign the received instance ID
                            modelEntity.components[InstanceIDComponent.self] = InstanceIDComponent(id: instanceID)
                            
                            // Determine the target parent and add the entity
                            let targetParent: Entity?
                            let transformToSet: simd_float4x4 = matrix // The transform received in the payload
                            let syncMode = self.arViewModel?.currentSyncMode ?? .world // Get current sync mode

                            // Check if the payload indicates relativity AND we are in a relative mode (Image or Object)
                            if isRelativeToImageAnchor, (syncMode == .imageTarget || syncMode == .objectTarget), let sharedAnchor = self.arViewModel?.sharedAnchorEntity {
                                // --- Image or Object Target Mode ---
                                targetParent = sharedAnchor
                                // Ensure shared anchor is in the scene graph before parenting
                                #if os(iOS)
                                if sharedAnchor.scene == nil, let scene = self.arViewModel?.currentScene {
                                     // Check if it's already in the scene's anchor list but not linked
                                     if let existingAnchor = scene.anchors.first(where: { $0 == sharedAnchor }) {
                                         print("SharedAnchorEntity found in scene anchors but scene property was nil (iOS). Using existing.")
                                     } else {
                                         scene.addAnchor(sharedAnchor)
                                         print("Added sharedAnchorEntity to scene in handleAddModel (iOS).")
                                     }
                                }
                                #elseif os(visionOS)
                                // On visionOS, RealityView manages adding anchors. Check if it's part of the scene graph.
                                if sharedAnchor.scene == nil {
                                     // It might be added by RealityView later. We might need to defer parenting or rely on the update loop.
                                     // For now, proceed assuming it will be available.
                                     print("Warning: SharedAnchorEntity scene is nil on visionOS during handleAddModel. Proceeding with parenting.")
                                }
                                #endif

                                // Check again if the anchor is ready (has a non-identity transform or is in scene)
                                let sharedAnchorWorldTransform = sharedAnchor.transformMatrix(relativeTo: nil)
                                if sharedAnchorWorldTransform == matrix_identity_float4x4 && sharedAnchor.scene == nil {
                                     print("Error: SharedAnchorEntity is not ready (identity transform and not in scene). Cannot add received model \(payload.modelType) relative to it.")
                                     // Optionally fallback to world placement or skip
                                     return
                                }

                                print("Target parent for \(payload.modelType) is sharedAnchorEntity.")
                                // The received transform `matrix` is ALREADY RELATIVE to the shared anchor. Apply it directly.
                                modelEntity.transform.matrix = transformToSet

                            } else {
                                // --- World Mode (or received non-relative transform) ---
                                if isRelativeToImageAnchor {
                                     print("Warning: Received relative transform flag for \(payload.modelType) but applying as world transform because current mode is \(syncMode.rawValue).")
                                }
                                #if os(iOS)
                                // On iOS, create a new AnchorEntity at the received world transform and add the model to it.
                                let worldAnchor = AnchorEntity(world: transformToSet)
                                targetParent = worldAnchor
                                // Add the anchor to the scene
                                if let scene = self.arViewModel?.currentScene {
                                    scene.addAnchor(worldAnchor)
                                    print("Added new world AnchorEntity to scene for received model \(payload.modelType) (iOS).")
                                } else {
                                     print("Warning: No scene found, cannot add world anchor for \(payload.modelType) (iOS).")
                                     return
                                }
                                // Model's transform relative to its own anchor is identity
                                modelEntity.transform = Transform()

                                #elseif os(visionOS)
                                // On visionOS, parent under the predefined 'modelAnchor' if available.
                                if let scene = self.arViewModel?.currentScene,
                                   let modelAnchor = scene.findEntity(named: "modelAnchor") as? AnchorEntity {
                                    targetParent = modelAnchor
                                    print("Target parent for \(payload.modelType) is modelAnchor (visionOS).")
                                    // The received transform `matrix` is a world transform. Set it relative to nil.
                                    // The entity will be added to modelAnchor below.
                                    modelEntity.setTransformMatrix(transformToSet, relativeTo: nil)
                                } else {
                                    // Fallback if modelAnchor isn't found (shouldn't happen ideally)
                                    print("Warning: modelAnchor not found in visionOS scene. Cannot place received model \(payload.modelType).")
                                    // Maybe add directly to scene content if possible, but RealityView manages this.
                                    targetParent = nil // Indicate failure to find parent
                                }
                                #else
                                // Fallback for other potential platforms
                                targetParent = nil
                                print("Warning: Unsupported platform for world mode placement in handleAddModel.")
                                #endif
                            }

                            // Add the model entity to the determined parent if found
                            if let parent = targetParent {
                                parent.addChild(modelEntity)
                                print("Added received model \(payload.modelType) (InstanceID: \(instanceID)) to parent \(parent.name). Relative: \(isRelativeToImageAnchor)")

                                // Register the entity (owned by peer) - Ensure InstanceID is set first!
                                print("Registering received entity \(modelEntity.id) with InstanceID \(instanceID)")
                                self.registerEntity(modelEntity, modelType: modelType, ownedByLocalPeer: false)

                                // Add to ModelManager's tracking (using the guaranteed strong reference)
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
            let instanceID = payload.instanceID
            print("Received removeModel request for InstanceID: \(instanceID) from \(peerID.displayName)")

            // Find the entity with this instance ID in the lookup
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

                let model = self.modelManager.modelDict[currentEntity]
                if let model = model {
                    print("handleRemoveModel: Found model \(model.modelType.rawValue) in ModelManager for InstanceID \(instanceID). Calling removeModel(broadcast: false).")
                    // Call removeModel with broadcast: false to prevent loop
                    // Use Task with MainActor to safely call the isolated method
                    Task { @MainActor in
                        // Pass the specific model instance found
                        self.modelManager.removeModel(model, broadcast: false)
                        print("handleRemoveModel: Successfully called modelManager.removeModel for \(model.modelType.rawValue) (InstanceID: \(instanceID))")
                    }
                    
                    // Also unregister from connectivity service *after* confirming removal starts
                    // Note: modelManager.removeModel should ideally handle unregistration now.
                    // self.unregisterEntity(currentEntity) // Let removeModel handle unregistration
                    
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
            print("handleAnchorWithTransform: modelID=\(payload.modelID)")
            
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
            
            // Process on main thread for UI updates
            DispatchQueue.main.async(execute: DispatchWorkItem(block: {
                let matrix = simd_float4x4.fromArray(payload.transform)
                let isRelativeToImageAnchor = payload.isRelativeToImageAnchor ?? false
                
                // First try to find the entity by instanceID (most reliable)
                let instanceID = payload.modelID // modelID now holds the instanceID
                print("Looking for entity with InstanceID: \(instanceID) in entityLookup (\(self.entityLookup.count) entries)")
                // Log available instance IDs for debugging
                // self.entityLookup.values.forEach { print("  - Found in lookup: \($0.name), InstanceID: \($0.components[InstanceIDComponent.self]?.id ?? "nil")") }
                
                if let entity = self.entityLookup.values.first(where: { $0.components[InstanceIDComponent.self]?.id == instanceID }) {
                     print("Found entity \(entity.name) by instance ID: \(instanceID) to update transform.")
                     
                     guard let arViewModel = self.arViewModel else {
                         print("ARViewModel not found, cannot update transform for \(instanceID)")
                         return
                     }
                    
                    // Determine the expected parent based on the received flag and current sync mode
                    let expectedParent: Entity?
                    let syncMode = arViewModel.currentSyncMode
                    if isRelativeToImageAnchor && (syncMode == .imageTarget || syncMode == .objectTarget) {
                        // --- Image or Object Target Mode ---
                        expectedParent = arViewModel.sharedAnchorEntity
                        if expectedParent?.scene == nil {
                             print("Warning: Expected parent (sharedAnchorEntity) for relative transform is not in scene. Cannot reliably update transform for \(instanceID).")
                             // Attempt to apply world transform instead? Or just skip? Skip for now.
                             return
                        }
                    } else {
                        // World mode - the parent should ideally be an AnchorEntity placed in the world.
                        // If the entity is directly under the scene, its transform is world transform.
                        // If it's under an AnchorEntity, its transform is relative to that anchor.
                        // Let's assume for world mode, the transform received IS the world transform.
                        // We might need to adjust the entity's parentage if it's currently under the image anchor.
                        expectedParent = nil // Representing world space (or an appropriate world anchor)
                    }

                    // --- Reparenting and Transform Logic ---
                    let currentParent = entity.parent

                    if isRelativeToImageAnchor && (syncMode == .imageTarget || syncMode == .objectTarget) {
                        // --- Image or Object Target Mode ---
                        // Ensure parent is sharedAnchorEntity
                        if currentParent !== arViewModel.sharedAnchorEntity {
                            print("Reparenting \(instanceID) to sharedAnchorEntity for \(syncMode.rawValue) mode.")
                            // Ensure shared anchor is in scene first (iOS mainly)
                            #if os(iOS)
                            if arViewModel.sharedAnchorEntity.scene == nil, let scene = arViewModel.currentScene {
                                scene.addAnchor(arViewModel.sharedAnchorEntity)
                            }
                            #endif
                            if arViewModel.sharedAnchorEntity.scene != nil {
                                entity.setParent(arViewModel.sharedAnchorEntity, preservingWorldTransform: true)
                            } else {
                                print("Warning: Cannot reparent \(instanceID) to sharedAnchorEntity because it's not in the scene.")
                                // Skip transform update if reparenting failed
                                return
                            }
                        }
                        // Apply the received transform (which is relative to sharedAnchorEntity)
                        entity.transform.matrix = matrix

                    } else {
                        // --- World Mode (or received non-relative transform) ---
                        if isRelativeToImageAnchor {
                             print("Warning: Received relative transform flag for \(instanceID) but applying as world transform because current mode is \(syncMode.rawValue).")
                        }
                        // Ensure parent is NOT sharedAnchorEntity. Move to appropriate world anchor.
                        if currentParent === arViewModel.sharedAnchorEntity {
                             print("Reparenting \(instanceID) from sharedAnchorEntity to World mode parent.")
                             #if os(iOS)
                             // Create a new world anchor at the target world position and reparent.
                             let worldAnchor = AnchorEntity(world: matrix)
                             if let scene = arViewModel.currentScene {
                                 scene.addAnchor(worldAnchor)
                                 entity.setParent(worldAnchor, preservingWorldTransform: false) // World transform is handled by anchor
                                 entity.transform = Transform() // Reset local transform
                             } else {
                                 print("Warning: Cannot reparent \(instanceID) to world anchor (iOS) - scene missing.")
                                 return // Skip update
                             }
                             #elseif os(visionOS)
                             // Reparent to the 'modelAnchor'
                             if let scene = arViewModel.currentScene, let modelAnchor = scene.findEntity(named: "modelAnchor") as? AnchorEntity {
                                 entity.setParent(modelAnchor, preservingWorldTransform: true)
                                 // Apply the received world transform after reparenting
                                 entity.setTransformMatrix(matrix, relativeTo: nil)
                             } else {
                                 print("Warning: Cannot reparent \(instanceID) to modelAnchor (visionOS) - anchor missing.")
                                 return // Skip update
                             }
                             #endif
                        } else {
                             // Already in world space (or should be). Apply the received world transform.
                             entity.setTransformMatrix(matrix, relativeTo: nil)
                        }
                    }
                    // --- End Reparenting ---

                    // Update the LastTransformComponent cache *after* applying
                    entity.components[LastTransformComponent.self] = LastTransformComponent(matrix: entity.transform.matrix)

                    print("Applied transform to \(instanceID). RelativeToShared: \(isRelativeToImageAnchor), Mode: \(syncMode.rawValue)")
                    return
                }

                // Fallback: Try to find the entity by its model type (Less reliable, keep as last resort)
                if let modelTypeStr = payload.modelType {
                    // Check model manager
                    for (entity, model) in self.modelManager.modelDict {
                        if model.modelType.rawValue.lowercased() == modelTypeStr.lowercased() {
                            self.applyTransformToFallbackEntity(entity: entity, matrix: matrix, isRelative: isRelativeToImageAnchor)
                            return
                        }
                    }

                    // Then check if any matching entities in the lookup
                    for (_, entity) in self.entityLookup {
                        if let component = entity.components[ModelTypeComponent.self],
                           let modelTypeStr = payload.modelType,
                           component.type.rawValue.lowercased() == modelTypeStr.lowercased() {
                            self.applyTransformToFallbackEntity(entity: entity, matrix: matrix, isRelative: isRelativeToImageAnchor)
                            return
                        }
                    }
                }

                // Last resort: Try traditional entity ID matching if all else fails
                for (entityID, entity) in self.entityLookup {
                     if entityID.stringValue == instanceID {
                         self.applyTransformToFallbackEntity(entity: entity, matrix: matrix, isRelative: isRelativeToImageAnchor)
                         return
                     }
                 }
                
                print("Could not find entity with instanceID \(instanceID) for transform update")
            }))
        } catch {
            print("Error decoding ModelTransformPayload: \(error)")
        }
    }
    
    #if os(iOS)
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
    #endif

    // Helper to apply transform in fallback scenarios, considering sync mode
    private func applyTransformToFallbackEntity(entity: Entity, matrix: simd_float4x4, isRelative: Bool) {
        guard let arViewModel = self.arViewModel else { return }
        let syncMode = arViewModel.currentSyncMode

        if isRelative && (syncMode == .imageTarget || syncMode == .objectTarget) {
            // Apply relative transform, reparenting if necessary
            if let currentParent = entity.parent, currentParent === arViewModel.sharedAnchorEntity {
                entity.transform.matrix = matrix // Already correct parent
            } else {
                // Reparent to shared anchor first
                print("Fallback: Reparenting \(entity.name) to sharedAnchorEntity for relative transform.")
                entity.removeFromParent()
                arViewModel.sharedAnchorEntity.addChild(entity)
                entity.transform.matrix = matrix // Apply relative transform
            }
        } else {
            // Apply world transform
            if isRelative {
                 print("Fallback Warning: Received relative transform flag for \(entity.name) but applying as world transform because current mode is \(syncMode.rawValue).")
            }
            // Ensure parent is not the shared anchor if it is currently
            if let currentParent = entity.parent, currentParent === arViewModel.sharedAnchorEntity {
                 print("Fallback: Reparenting \(entity.name) from sharedAnchorEntity to world parent.")
                 // On iOS/visionOS, simply removing from parent and setting world transform might suffice
                 // if the entity gets re-added to the scene root or appropriate world anchor elsewhere.
                 // For simplicity here, just remove and set world transform.
                 entity.removeFromParent()
                 // Ideally, re-add to the correct world anchor (e.g., modelAnchor on visionOS)
                 // This might require more context. For now, just set world transform.
                 entity.setTransformMatrix(matrix, relativeTo: nil)
            } else {
                 // Already in world space (or should be), just set world transform
                 entity.setTransformMatrix(matrix, relativeTo: nil)
            }
        }
        print("Fallback: Applied transform to \(entity.name). Relative: \(isRelative), Mode: \(syncMode.rawValue)")
    }
}