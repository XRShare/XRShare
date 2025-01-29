//MultipeerConnectivity
import MultipeerConnectivity

protocol MultipeerSessionDelegate: AnyObject {
    func receivedData(_ data: Data, from peerID: MCPeerID)
    func peerDidChangeState(peerID: MCPeerID, state: MCSessionState)
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
        print("Starting advertising and browsing")
        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
    }

    func sendToAllPeers(_ data: Data, dataType: DataType) {
        guard session.connectedPeers.count > 0 else {
            print("No connected peers to send data to.")
            return
        }
        var sendData = Data([dataType.rawValue])
        sendData.append(data)
        do {
            try session.send(sendData, toPeers: session.connectedPeers, with: .reliable)
            print("Data of type \(dataType) sent to all peers")
        } catch {
            print("Error sending data: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCSessionDelegate
extension MultipeerSession: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.delegate?.peerDidChangeState(peerID: peerID, state: state)
        }
        print("Peer \(peerID.displayName) did change state: \(state.rawValue)")
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.delegate?.receivedData(data, from: peerID)
        }
    }

    // Required but unused delegate methods
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MultipeerSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("Failed to start advertising: \(error.localizedDescription)")
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("Received invitation from peer \(peerID.displayName)")
        delegate?.didReceiveInvitation(from: peerID, invitationHandler: invitationHandler)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerSession: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Failed to start browsing: \(error.localizedDescription)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        // Prevent multiple invitations
        if !session.connectedPeers.contains(peerID) && peerID != myPeerID {
            print("Found peer \(peerID.displayName), inviting to session")
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        } else {
            print("Already connected to \(peerID.displayName) or it's ourselves; not inviting.")
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Lost connection to peer \(peerID.displayName)")
    }
}
