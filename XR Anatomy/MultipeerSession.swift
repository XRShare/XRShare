// Handles aspects of the multipeer connections

import MultipeerConnectivity

protocol MultipeerSessionDelegate: AnyObject {
    func receivedData(_ data: Data, from peerID: MCPeerID)
    func peerDidChangeState(peerID: MCPeerID, state: MCSessionState)
    func didReceiveInvitation(from peerID: MCPeerID, sessionID: String, invitationHandler: @escaping (Bool, MCSession?) -> Void)
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
    var foundPeers: [(peerID: MCPeerID, sessionID: String, sessionName: String)] = []  // For viewers to keep track of found peers

    init(sessionID: String?, sessionName: String?, userRole: UserRole) {
        self.sessionID = sessionID
        self.sessionName = sessionName
        self.userRole = userRole

        // Generate a unique display name by appending a random UUID
        let uniqueSuffix = UUID().uuidString.prefix(4)
        let deviceName = UIDevice.current.name
        let displayName = "\(deviceName)-\(uniqueSuffix)"
        self.myPeerID = MCPeerID(displayName: displayName)

        super.init()
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self

        // Set up advertiser and browser but do not start them yet
        switch userRole {
        case .host:
            // Hosts advertise their session ID and session Name
            var discoveryInfo = [String: String]()
            if let sessionID = sessionID {
                discoveryInfo["sessionID"] = sessionID
            }
            if let sessionName = sessionName {
                discoveryInfo["sessionName"] = sessionName
            }
            self.discoveryInfo = discoveryInfo
            advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: discoveryInfo, serviceType: serviceType)
            advertiser?.delegate = self
            // Do not start advertising yet
        case .viewer:
            // Viewers browse for available sessions
            browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
            browser?.delegate = self
            // Do not start browsing yet
        case .openSession:
            // Collaborate mode: both advertise and browse
            var discoveryInfo = [String: String]()
            if let sessionID = sessionID {
                discoveryInfo["sessionID"] = sessionID
            }
            if let sessionName = sessionName {
                discoveryInfo["sessionName"] = sessionName
            }
            self.discoveryInfo = discoveryInfo
            advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: discoveryInfo, serviceType: serviceType)
            advertiser?.delegate = self

            browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
            browser?.delegate = self
            // Do not start advertising or browsing yet
        }
    }

    // New start() method to begin advertising or browsing
    func start() {
        switch userRole {
        case .host:
            advertiser?.startAdvertisingPeer()
            print("Started advertising as host.")
        case .viewer:
            browser?.startBrowsingForPeers()
            print("Started browsing for peers as viewer.")
        case .openSession:
            advertiser?.startAdvertisingPeer()
            browser?.startBrowsingForPeers()
            print("Started advertising and browsing in open session mode.")
        }
    }

    deinit {
        disconnect()
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
    }

    func invitePeer(_ peerID: MCPeerID, sessionID: String) {
        guard let browser = browser else {
            print("Browser is nil, cannot invite peer.")
            return
        }
        guard let session = session else {
            print("Session is nil, cannot invite peer.")
            return
        }
        invitedPeerIDs.append(peerID)
        let context = sessionID.data(using: .utf8)
        print("Inviting peer \(peerID.displayName) with context sessionID \(sessionID)")
        browser.invitePeer(peerID, to: session, withContext: context, timeout: 10)
    }

    func sendToAllPeers(_ data: Data, dataType: DataType) {
        guard let session = session, session.connectedPeers.count > 0 else {
            // print("No connected peers to send data to.")
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

    func sendToPeer(_ data: Data, peerID: MCPeerID, dataType: DataType) {
        guard let session = session else {
            print("Session is nil, cannot send data to peer.")
            return
        }
        var sendData = Data([dataType.rawValue])
        sendData.append(data)
        do {
            try session.send(sendData, toPeers: [peerID], with: .reliable)
            print("Data of type \(dataType) sent to \(peerID.displayName)")
        } catch {
            print("Error sending data to \(peerID.displayName): \(error.localizedDescription)")
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

        print("MultipeerSession disconnected and resources cleaned up.")
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
        // Automatically accept invitations in host mode
        print("Host received invitation from peer \(peerID.displayName)")
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MultipeerSession: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("Failed to start browsing: \(error.localizedDescription)")
    }

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        guard peerID != myPeerID else {
            print("Found myself, ignoring.")
            return
        }
        let sessionID = info?["sessionID"] ?? "Unknown"
        let sessionName = info?["sessionName"] ?? "Unknown"
        print("Found peer \(peerID.displayName) with session ID \(sessionID) and session name \(sessionName)")
        foundPeers.append((peerID: peerID, sessionID: sessionID, sessionName: sessionName))
        DispatchQueue.main.async {
            self.delegate?.foundPeer(peerID: peerID, sessionID: sessionID, sessionName: sessionName)
        }

        // Auto-invite in Collaborate mode
        if userRole == .openSession {
            print("Collaborate mode: auto-inviting peer \(peerID.displayName)")
            invitePeer(peerID, sessionID: self.sessionID ?? "Unknown")
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("Lost connection to peer \(peerID.displayName)")
        if let index = foundPeers.firstIndex(where: { $0.peerID == peerID }) {
            foundPeers.remove(at: index)
            DispatchQueue.main.async {
                self.delegate?.lostPeer(peerID: peerID)
            }
        }
    }
}
