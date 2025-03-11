#if os(visionOS)
import Foundation
import RealityKit
import MultipeerConnectivity

/// Typealias matching Apple’s internal Identifier.
public typealias Identifier = Entity.ID

/// A minimal custom peer type conforming to `SynchronizationPeerID`.
public final class CustomPeerID: SynchronizationPeerID, Hashable {
    private let uuid = UUID()
    
    public static func == (lhs: CustomPeerID, rhs: CustomPeerID) -> Bool {
        lhs.uuid == rhs.uuid
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(uuid)
    }
}

/// A custom connectivity service to replicate Apple’s MultipeerConnectivityService for visionOS.
public final class MyCustomConnectivityService: NSObject, SynchronizationService {
    
    // MARK: - Public Types & Properties
    
    public typealias Identifier = Entity.ID
    public let session: MCSession
    public var localPeerIdentifier: any SynchronizationPeerID { localPeer }
    
    // MARK: - Private Storage
    
    private var entityLookup: [Identifier: Entity] = [:]
    private var entityOwners: [Identifier: CustomPeerID] = [:]
    public let localPeer = CustomPeerID()
    private var isSyncing = false
    
    // MARK: - Initialization
    
    public init(session: MCSession) throws {
        self.session = session
        super.init()
        self.session.delegate = self
    }
    
    // MARK: - Public Synchronization Methods
    
    public func startSync() {
        guard !isSyncing else { return }
        isSyncing = true
        print("MyCustomConnectivityService: startSync() called.")
    }
    
    public func stopSync() {
        guard isSyncing else { return }
        isSyncing = false
        print("MyCustomConnectivityService: stopSync() called.")
    }
    
    public func setHandshake(count: UInt32, timeoutMs: UInt32) {
        print("Configured handshake: count=\(count), timeout=\(timeoutMs)ms")
    }
    
    // MARK: - SynchronizationService Protocol Conformance
    
    public func entity(for identifier: Identifier) -> Entity? {
        return entityLookup[identifier]
    }
    
    public func owner(of entity: Entity) -> (any SynchronizationPeerID)? {
        return entityOwners[entity.id]
    }
    
    @discardableResult
    public func giveOwnership(of entity: Entity, toPeer: any SynchronizationPeerID) -> Bool {
        guard let newOwner = toPeer as? CustomPeerID else {
            return false
        }
        entityOwners[entity.id] = newOwner
        return true
    }
    
    // MARK: - Entity Management
    
    public func registerEntity(_ entity: Entity) {
        entityLookup[entity.id] = entity
        entityOwners[entity.id] = localPeer
    }
    
    // MARK: - Bridging Methods (Simplified)
    
    /// Converts a peer ID into its core pointer representation.
    public func __fromCore(peerID: __PeerIDRef) -> (any SynchronizationPeerID)? {
        let rawPointer = unsafeBitCast(peerID, to: UnsafeRawPointer.self)
        return Unmanaged<CustomPeerID>.fromOpaque(rawPointer).takeUnretainedValue()
    }

    public func __toCore(peerID: any SynchronizationPeerID) -> __PeerIDRef {
        guard let customID = peerID as? CustomPeerID else {
            fatalError("Unexpected peer type for bridging.")
        }
        let rawPointer = UnsafeRawPointer(Unmanaged.passUnretained(customID).toOpaque())
        return unsafeBitCast(rawPointer, to: __PeerIDRef.self)
    }
}

// MARK: - MCSessionDelegate Implementation

extension MyCustomConnectivityService: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("Peer \(peerID.displayName) changed state to \(state)")
    }
    
    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        print("Received data from peer \(peerID.displayName)")
    }
    
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        print("Received unexpected stream '\(streamName)' from \(peerID.displayName); ignoring.")
    }
    
    public func session(_ session: MCSession,
                        didStartReceivingResourceWithName resourceName: String,
                        fromPeer peerID: MCPeerID,
                        with progress: Progress) {
        print("Started receiving resource '\(resourceName)' from \(peerID.displayName).")
    }
    
    public func session(_ session: MCSession,
                        didFinishReceivingResourceWithName resourceName: String,
                        fromPeer peerID: MCPeerID,
                        at localURL: URL?,
                        withError error: Error?) {
        if let error = error {
            print("Error receiving resource '\(resourceName)' from \(peerID.displayName): \(error.localizedDescription)")
        } else {
            print("Finished receiving resource '\(resourceName)' from \(peerID.displayName).")
        }
    }
}
#endif
