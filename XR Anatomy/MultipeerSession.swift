import MultipeerConnectivity

protocol MultipeerSessionDelegate: AnyObject {
    func receivedData(_ data: Data, from peerID: MCPeerID)
    func peerDidChangeState(peerID: MCPeerID, state: MCSessionState)
    func didReceiveInvitation(from peerID: MCPeerID, sessionID: String,
                              invitationHandler: @escaping (Bool, MCSession?) -> Void)
    func foundPeer(peerID: MCPeerID, sessionID: String, sessionName: String)
    func lostPeer(peerID: MCPeerID)
}

class MultipeerSession: NSObject {
    private let serviceType = "ar-collab"
    let myPeerID: MCPeerID
    var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    weak var delegate: MultipeerSessionDelegate?
    private var discoveryInfo: [String: String]?
    private var invitedPeerIDs: [MCPeerID] = []
    private var sessionID: String?
    private var sessionName: String?
    private var userRole: UserRole
    var foundPeers: [(peerID: MCPeerID, sessionID: String, sessionName: String)] = []

    init(sessionID: String?, sessionName: String?, userRole: UserRole) {
        self.sessionID = sessionID
        self.sessionName = sessionName
        self.userRole = userRole

        let uniqueSuffix = UUID().uuidString.prefix(4)
        let deviceName = UIDevice.current.name
        let displayName = "\(deviceName)-\(uniqueSuffix)"
        self.myPeerID = MCPeerID(displayName: displayName)

        super.init()

        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self

        switch userRole {
        case .host:
            var di = [String: String]()
            if let sid = sessionID { di["sessionID"] = sid }
            if let sn = sessionName { di["sessionName"] = sn }
            discoveryInfo = di
            advertiser = MCNearbyServiceAdvertiser(peer: myPeerID,
                                                   discoveryInfo: di,
                                                   serviceType: serviceType)
            advertiser?.delegate = self
        case .viewer:
            browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
            browser?.delegate = self
        case .openSession:
            var di = [String: String]()
            if let sid = sessionID { di["sessionID"] = sid }
            if let sn = sessionName { di["sessionName"] = sn }
            discoveryInfo = di
            advertiser = MCNearbyServiceAdvertiser(peer: myPeerID,
                                                   discoveryInfo: di,
                                                   serviceType: serviceType)
            advertiser?.delegate = self

            browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
            browser?.delegate = self
        }
    }

    func start() {
        switch userRole {
        case .host:
            advertiser?.startAdvertisingPeer()
        case .viewer:
            browser?.startBrowsingForPeers()
        case .openSession:
            advertiser?.startAdvertisingPeer()
            browser?.startBrowsingForPeers()
        }
    }

    deinit {
        disconnect()
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
    }

    func invitePeer(_ peerID: MCPeerID, sessionID: String) {
        guard let browser = browser, let session = session else { return }
        invitedPeerIDs.append(peerID)
        let ctx = sessionID.data(using: .utf8)
        browser.invitePeer(peerID, to: session, withContext: ctx, timeout: 10)
    }

    func sendToAllPeers(_ data: Data, dataType: DataType) {
        guard let session = session, session.connectedPeers.count > 0 else { return }
        var packet = Data([dataType.rawValue])
        packet.append(data)
        do {
            try session.send(packet, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            print("Send error: \(error)")
        }
    }

    func sendToPeer(_ data: Data, peerID: MCPeerID, dataType: DataType) {
        guard let session = session else { return }
        var packet = Data([dataType.rawValue])
        packet.append(data)
        do {
            try session.send(packet, toPeers: [peerID], with: .reliable)
        } catch {
            print("Send error to \(peerID.displayName): \(error)")
        }
    }

    func disconnect() {
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        browser = nil
        session?.disconnect()
        session?.delegate = nil
        session = nil
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
    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerSession: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        print("Failed to start adv: \(error)")
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // For host or openSession, auto-accept
        if userRole == .host || userRole == .openSession {
            invitationHandler(true, session)
        } else {
            // If viewer is receiving invites from other hosts, might handle differently
            // Or rely on your existing code
            if let ctx = context, let sid = String(data: ctx, encoding: .utf8) {
                delegate?.didReceiveInvitation(from: peerID, sessionID: sid, invitationHandler: invitationHandler)
            } else {
                invitationHandler(false, nil)
            }
        }
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
        if userRole == .openSession {
            invitePeer(peerID, sessionID: sessionID ?? "Unknown")
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser,
                 lostPeer peerID: MCPeerID) {
        if let i = foundPeers.firstIndex(where: { $0.peerID == peerID }) {
            foundPeers.remove(at: i)
            delegate?.lostPeer(peerID: peerID)
        }
    }
}
