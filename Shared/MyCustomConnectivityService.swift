import Foundation
import RealityKit
import MultipeerConnectivity

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
        return "\(self)"
    }
}

// MARK: - MyCustomConnectivityService
/// A custom connectivity service for RealityKit scene synchronization
class MyCustomConnectivityService: NSObject {
    // MARK: - Properties
    private var multipeerSession: MultipeerSession
    weak var arViewModel: ARViewModel?
    weak var modelManager: ModelManager?
    
    // Entity tracking
    private var entityLookup: [Entity.ID: Entity] = [:]
    private var locallyOwnedEntities: Set<Entity.ID> = []
    
    // Queue for handling received data
    private let receivingQueue = DispatchQueue(label: "com.xranatomy.receivingQueue")
    
    // MARK: - Initialization
    
    init(multipeerSession: MultipeerSession, arViewModel: ARViewModel?, modelManager: ModelManager? = nil) {
        self.multipeerSession = multipeerSession
        self.arViewModel = arViewModel
        self.modelManager = modelManager
        super.init()
        
        print("MyCustomConnectivityService initialized")
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
    func sendModelTransform(entity: Entity, modelType: ModelType? = nil) {
        guard multipeerSession.session.connectedPeers.count > 0 else { return }
        
        let transformArray = entity.transform.matrix.toArray()
        let modelTypeString = modelType?.rawValue
        let modelID = "model-\(entity.id.stringValue)"
        
        let payload = ModelTransformPayload(
            modelID: modelID,
            transform: transformArray,
            modelType: modelTypeString
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
                self.handleModelTransform(payload, from: peerID)
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
            default:
                print("Received unsupported data type: \(dataType)")
            }
        }
    }
}

// MARK: - Data Type Handlers
private extension MyCustomConnectivityService {
    func handleReceivedData(dataType: DataType, payload: Data, from peerID: MCPeerID) {
        switch dataType {
        case .anchorWithTransform:
            handleAnchorWithTransform(payload, from: peerID)
        case .modelTransform:
            handleModelTransform(payload, from: peerID)
        #if os(iOS)
        case .collaborationData:
            handleCollaborationData(payload, from: peerID)
        case .removeAnchors:
            handleRemoveAnchors(payload, from: peerID)
        #endif
        default:
            print("Received data type \(dataType) which is unimplemented.")
        }
    }
    
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
                                    
                                    // Add to model manager if available
                                    if let modelManager = self.modelManager {
                                        modelManager.modelDict[modelEntity] = model
                                        modelManager.placedModels.append(model)
                                    }
                                    
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
    
    func handleModelTransform(_ data: Data, from peerID: MCPeerID) {
        do {
            let payload = try JSONDecoder().decode(ModelTransformPayload.self, from: data)
            
            // Process on main thread for UI updates
            DispatchQueue.main.async {
                let matrix = simd_float4x4.fromArray(payload.transform)
                
                // Try to find the entity by its model type first
                if let modelTypeStr = payload.modelType {
                    // First check model manager
                    if let modelManager = self.modelManager {
                        for (entity, model) in modelManager.modelDict {
                            if model.modelType.rawValue.lowercased() == modelTypeStr.lowercased() {
                                entity.transform.matrix = matrix
                                return
                            }
                        }
                    }
                    
                    // Then check if any matching entities in the lookup
                    for (_, entity) in self.entityLookup {
                        if let component = entity.components[ModelTypeComponent.self],
                           component.type.rawValue.lowercased() == modelTypeStr.lowercased() {
                            entity.transform.matrix = matrix
                            return
                        }
                    }
                }
                
                // Fallback to entity ID lookup
                let idStr = payload.modelID.replacingOccurrences(of: "model-", with: "")
                // Try to match by string representation
                for (entityID, entity) in self.entityLookup {
                    if entityID.stringValue == idStr {
                        entity.transform.matrix = matrix
                        return
                    }
                }
            }
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
}
