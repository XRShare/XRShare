//
//  MultipeerSession.swift
//  XR Anatomy
//
//  Created by ...
//

import MultipeerConnectivity
import Foundation

protocol MultipeerSessionDelegate: AnyObject {
    func session(_ session: MultipeerSession, didReceiveData data: Data, from peerID: MCPeerID)
    func session(_ session: MultipeerSession, peer peerID: MCPeerID, didChange state: MCSessionState)
    func didReceiveInvitation(from peerID: MCPeerID, invitationHandler: @escaping (Bool, MCSession?) -> Void)
    func foundPeer(peerID: MCPeerID, sessionID: String, sessionName: String)
}

class MultipeerSession: NSObject {
    private let serviceType = "xr-anatomy"
    let session: MCSession
    private let myPeerID: MCPeerID
    private let advertiser: MCNearbyServiceAdvertiser
    private let browser: MCNearbyServiceBrowser
    private var discoveryInfo: [String: String]? // Store discovery info
    
    weak var delegate: MultipeerSessionDelegate?
    
    // MARK: - Initialization
    
    // Accept discoveryInfo in the initializer
    init(serviceName: String = "xr-anatomy", displayName: String, discoveryInfo: [String: String]? = nil) {
        self.discoveryInfo = discoveryInfo // Store it
        
        #if os(iOS)
        self.myPeerID = MCPeerID(displayName: displayName)
        #else
        self.myPeerID = MCPeerID(displayName: displayName)
        #endif
        
        // Create the session
        self.session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        
        // Create advertiser using the provided discoveryInfo
        self.advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: self.discoveryInfo, // Use stored discovery info
            serviceType: serviceType
        )
        
        // Create browser
        self.browser = MCNearbyServiceBrowser(
            peer: myPeerID,
            serviceType: serviceType
        )
        
        super.init()
        
        // Set up delegates
        session.delegate = self
        advertiser.delegate = self
        browser.delegate = self
        
        print("MultipeerSession initialized - ID: \(myPeerID.displayName)")
    }
    
    deinit {
        stopBrowsingAndAdvertising()
    }
    
    // MARK: - Public Methods
    
    func startBrowsingAndAdvertising() {
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        print("Started browsing and advertising")
    }
    
    func stopBrowsingAndAdvertising() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
        print("Stopped browsing and advertising")
    }
    
    func sendToPeer(_ data: Data, peerID: MCPeerID, dataType: DataType, reliable: Bool = true) {
        do {
            let typeData = Data([dataType.rawValue])
            var completeData = typeData
            completeData.append(data)
            
            if !session.connectedPeers.contains(peerID) {
                print("Error: Tried to send to disconnected peer \(peerID.displayName)")
                return
            }
            
            try session.send(completeData, toPeers: [peerID], with: reliable ? .reliable : .unreliable)
        } catch {
            print("Error sending data to peer \(peerID.displayName): \(error)")
        }
    }
    
    func sendToAllPeers(_ data: Data, dataType: DataType, reliable: Bool = true) {
        guard !session.connectedPeers.isEmpty else { return }
        
        do {
            let typeData = Data([dataType.rawValue])
            var completeData = typeData
            completeData.append(data)
            
            try session.send(completeData, toPeers: session.connectedPeers, with: reliable ? .reliable : .unreliable)
        } catch {
            print("Error sending data to peers: \(error)")
        }
    }
    
    func invitePeer(_ peerID: MCPeerID) {
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
        print("Invited peer: \(peerID.displayName)")
    }
}

// MARK: - MCSessionDelegate
extension MultipeerSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.delegate?.session(self, peer: peerID, didChange: state)
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.delegate?.session(self, didReceiveData: data, from: peerID)
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used in this implementation
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used in this implementation
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used in this implementation
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        DispatchQueue.main.async {
            self.delegate?.didReceiveInvitation(from: peerID, invitationHandler: invitationHandler)
        }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Error advertising: \(error)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerSession: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        // Extract sessionID and sessionName from discovery info, provide defaults if missing
        let sessionID = info?["sessionID"] ?? UUID().uuidString // Generate a fallback ID if needed
        let sessionName = info?["sessionName"] ?? peerID.displayName // Use peer display name as fallback
        
        print("Found peer \(peerID.displayName) with discovery info: \(info ?? [:]) -> SessionName: \(sessionName), SessionID: \(sessionID)")
        
        DispatchQueue.main.async {
            self.delegate?.foundPeer(peerID: peerID, sessionID: sessionID, sessionName: sessionName)
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        // Don't need to handle lost peers separately - they will trigger a state change in the session
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Error browsing for peers: \(error)")
    }
}
