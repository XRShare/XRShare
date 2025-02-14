//
//  that.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-14.
//

import MultipeerConnectivity
import Foundation

protocol MultipeerSessionDelegate: AnyObject {
    func receivedData(_ data: Data, from peerID: MCPeerID)
    func peerDidChangeState(peerID: MCPeerID, state: MCSessionState)
    func didReceiveInvitation(from peerID: MCPeerID,
                              invitationHandler: @escaping (Bool, MCSession?) -> Void)
    func foundPeer(peerID: MCPeerID, sessionID: String, sessionName: String)
    func lostPeer(peerID: MCPeerID)
}

class MultipeerSession: NSObject {
    private let serviceType = "ar-collab"
    let myPeerID: MCPeerID
    var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    weak var delegate: MultipeerSessionDelegate?
    
    // For a host/openSession, we use discovery info:
    private var discoveryInfo: [String: String]?
    private var sessionID: String?
    private var sessionName: String?
    
    // For keeping track of found peers
    var foundPeers: [(peerID: MCPeerID, sessionID: String, sessionName: String)] = []
    
    init(sessionID: String? = nil, sessionName: String? = nil, discoveryInfo: [String:String]? = nil) {
        // Append a unique suffix so that the display name is unique.
        let uniqueSuffix = UUID().uuidString.prefix(4)
        let deviceName = UIDevice.current.name
        self.myPeerID = MCPeerID(displayName: "\(deviceName)-\(uniqueSuffix)")
        self.sessionID = sessionID
        self.sessionName = sessionName
        self.discoveryInfo = discoveryInfo
        
        super.init()
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        // For hosts and open sessions, advertise and for viewers, browse.
        if discoveryInfo != nil {
            advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: discoveryInfo, serviceType: serviceType)
            advertiser?.delegate = self
        }
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
    }
    
    func start() {
        advertiser?.startAdvertisingPeer()
        browser?.startBrowsingForPeers()
    }
    
    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
    }
    
    func invitePeer(_ peerID: MCPeerID, sessionID: String) {
        guard let browser = browser else { return }
        let context = sessionID.data(using: .utf8)
        browser.invitePeer(peerID, to: session, withContext: context, timeout: 10)
    }
    
    func sendToAllPeers(_ data: Data, dataType: DataType) {
        guard session.connectedPeers.count > 0 else { return }
        var packet = Data([dataType.rawValue])
        packet.append(data)
        do {
            try session.send(packet, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("Error sending data: \(error)")
        }
    }
}

extension MultipeerSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.delegate?.peerDidChangeState(peerID: peerID, state: state)
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.delegate?.receivedData(data, from: peerID)
        }
    }
    
    // Unused delegate methods:
    func session(_ session: MCSession,
                 didReceive stream: InputStream,
                 withName streamName: String,
                 fromPeer peerID: MCPeerID) { }
    func session(_ session: MCSession,
                 didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 with progress: Progress) { }
    func session(_ session: MCSession,
                 didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 at localURL: URL?,
                 withError error: Error?) { }
}

extension MultipeerSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        print("Failed to start advertising: \(error)")
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations (or delegate to UI as needed)
        delegate?.didReceiveInvitation(from: peerID, invitationHandler: invitationHandler)
    }
}

extension MultipeerSession: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser,
                 didNotStartBrowsingForPeers error: Error) {
        print("Failed to start browsing: \(error)")
    }
    
    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String : String]?) {
        guard peerID != myPeerID else { return }
        let sid = info?["sessionID"] ?? "Unknown"
        let sname = info?["sessionName"] ?? "Unknown"
        foundPeers.append((peerID, sid, sname))
        delegate?.foundPeer(peerID: peerID, sessionID: sid, sessionName: sname)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser,
                 lostPeer peerID: MCPeerID) {
        delegate?.lostPeer(peerID: peerID)
    }
}
