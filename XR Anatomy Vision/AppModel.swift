import SwiftUI
import MultipeerConnectivity

// A simple state machine for session pages
enum SessionPage {
    case mainMenu, joinSession, hostSession, inSession
}

enum ImmersiveSpaceState {
    case closed, inTransition, open
}

final class AppModel: ObservableObject, MultipeerSessionDelegate {
    @Published var currentPage: SessionPage = .mainMenu
    @Published var immersiveSpaceState: ImmersiveSpaceState = .closed
    
    // We store discovered sessions here to show in JoinSession
    @Published var availableSessions: [(peerID: MCPeerID, sessionName: String)] = []
    
    // For creating an "open" or "host" session
    var sessionID: String = ""
    var sessionName: String = ""
    var userRole: UserRole = .openSession  // from your existing code
    
    // The ID for the immersive space (matching XRAnatomy_visionOSApp)
    let immersiveSpaceID: String = "ImmersiveSpace"
    
    // MultiPeer session reference
    var multipeerSession: MultipeerSession?
    
    init() {
        // No auto-browsing here.
        // The user picks "Join" or "Host" from MainMenu,
        // then we call joinSession() or hostSession().
    }
    
    // MARK: - Hosting
    func hostSession() {
        // Generate an ID & name, or let the user set them first.
        self.sessionID = UUID().uuidString
        if sessionName.isEmpty {
            self.sessionName = "visionOS-Hosted"
        }
        
        // Create an advertiser session
        let discoveryInfo = [
            "sessionID": sessionID,
            "sessionName": sessionName
        ]
        
        self.multipeerSession = MultipeerSession(
            sessionID: sessionID,
            sessionName: sessionName,
            discoveryInfo: discoveryInfo
        )
        self.multipeerSession?.delegate = self
        self.multipeerSession?.start()
        
        print("Hosting session: ID=\(sessionID), Name=\(sessionName)")
    }
    
    // MARK: - Joining
    func joinSession() {
        // Create a browser session (nil discoveryInfo)
        self.multipeerSession = MultipeerSession(
            sessionID: nil,
            sessionName: nil,
            discoveryInfo: nil
        )
        self.multipeerSession?.delegate = self
        self.multipeerSession?.start()
        
        print("Joining a session (browsing).")
    }
    
    // MARK: - MultipeerSessionDelegate
    
    func receivedData(_ data: Data, from peerID: MCPeerID) {
        // If you want to handle custom data, do it here
    }
    
    func peerDidChangeState(peerID: MCPeerID, state: MCSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .connected:
                // Example: track connected peers
                let sessionName = "Session \(peerID.displayName)"
                if !self.availableSessions.contains(where: { $0.peerID == peerID }) {
                    self.availableSessions.append((peerID: peerID, sessionName: sessionName))
                }
            case .notConnected:
                self.availableSessions.removeAll { $0.peerID == peerID }
            default:
                break
            }
        }
    }
    
    func didReceiveInvitation(from peerID: MCPeerID, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Accept automatically, or prompt user. For now, auto-accept:
        invitationHandler(true, multipeerSession?.session)
    }
    
    func foundPeer(peerID: MCPeerID, sessionID: String, sessionName: String) {
        DispatchQueue.main.async {
            // The viewer sees these in JoinSession
            if !self.availableSessions.contains(where: { $0.peerID == peerID }) {
                self.availableSessions.append((peerID: peerID, sessionName: sessionName))
            }
        }
    }
    
    func lostPeer(peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.availableSessions.removeAll { $0.peerID == peerID }
        }
    }
}
