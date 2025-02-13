import MultipeerConnectivity

protocol MultipeerSessionDelegate: AnyObject {
    /// Called whenever data arrives from a peer
    func receivedData(_ data: Data, from peerID: MCPeerID)
    /// Called when a peer’s connection state changes
    func peerDidChangeState(peerID: MCPeerID, state: MCSessionState)
    /// Called when we get an invitation request
    func didReceiveInvitation(from peerID: MCPeerID, invitationHandler: @escaping (Bool, MCSession?) -> Void)
}

class MultipeerSession: NSObject {

    private let serviceType = "ar-collab"
    let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    var session: MCSession!

    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    weak var delegate: MultipeerSessionDelegate?

    override init() {
        super.init()
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        advertiser.delegate = self
        browser.delegate = self

        startAdvertisingAndBrowsing()
    }

    private func startAdvertisingAndBrowsing() {
        print("Starting advertising and browsing for peers…")
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    /// Send data (with a small leading byte for DataType) to all peers
    func sendToAllPeers(_ data: Data, dataType: DataType) {
        guard session.connectedPeers.count > 0 else {
            print("No connected peers to send data to.")
            return
        }
        var packet = Data([dataType.rawValue])
        packet.append(data)
        do {
            try session.send(packet, toPeers: session.connectedPeers, with: .reliable)
            print("Sent data of type \(dataType) to all peers.")
        } catch {
            print("Error sending data: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCSessionDelegate
extension MultipeerSession: MCSessionDelegate {
    func session(_ session: MCSession,
                 peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.delegate?.peerDidChangeState(peerID: peerID, state: state)
        }
        print("Peer \(peerID.displayName) changed state: \(state.rawValue)")
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.delegate?.receivedData(data, from: peerID)
        }
    }

    // The following are required but not used
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

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        print("Failed to start advertising: \(error.localizedDescription)")
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("Received invitation from peer \(peerID.displayName)")
        delegate?.didReceiveInvitation(from: peerID, invitationHandler: invitationHandler)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerSession: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser,
                 didNotStartBrowsingForPeers error: Error) {
        print("Failed to start browsing: \(error.localizedDescription)")
    }

    func browser(_ browser: MCNearbyServiceBrowser,
                 foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String : String]?) {
        // Prevent multiple invites
        if !session.connectedPeers.contains(peerID) && peerID != myPeerID {
            print("Found peer \(peerID.displayName), inviting to session")
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        } else {
            print("Already connected to \(peerID.displayName) or it's ourselves.")
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser,
                 lostPeer peerID: MCPeerID) {
        print("Lost peer \(peerID.displayName)")
    }
}
