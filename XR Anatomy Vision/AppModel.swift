import SwiftUI
import MultipeerConnectivity

// A simple state machine for session pages.
enum SessionPage {
    case mainMenu, joinSession, hostSession, inSession
}

enum ImmersiveSpaceState {
    case closed, inTransition, open
}

final class AppModel: ObservableObject, MultipeerSessionDelegate {
    @Published var currentPage: SessionPage = .mainMenu
    @Published var immersiveSpaceState: ImmersiveSpaceState = .closed
    @Published var availableSessions: [(peerID: MCPeerID, sessionName: String)] = []
    
    // An ID for the immersive space (used in XRAnatomy_visionOSApp.swift)
    let immersiveSpaceID: String = "ImmersiveSpace"
    
    var multipeerSession: MultipeerSession?
    
    init() {
        // For viewers, start browsing for sessions
        startBrowsing()
    }
    
    func startBrowsing() {
        // Create a multipeer session in viewer mode (no discovery info)
        multipeerSession = MultipeerSession(sessionID: nil, sessionName: nil, discoveryInfo: nil)
        multipeerSession?.delegate = self
        multipeerSession?.start()
    }
    
    // MARK: - MultipeerSessionDelegate Methods
    
    func receivedData(_ data: Data, from peerID: MCPeerID) {
        // Handle incoming session data here.
    }
    
    func peerDidChangeState(peerID: MCPeerID, state: MCSessionState) {
        DispatchQueue.main.async {
            if state == .connected {
                // For simplicity, add the connected peer to available sessions.
                let sessionName = "Session \(peerID.displayName)"
                if !self.availableSessions.contains(where: { $0.peerID == peerID }) {
                    self.availableSessions.append((peerID: peerID, sessionName: sessionName))
                }
            } else if state == .notConnected {
                self.availableSessions.removeAll { $0.peerID == peerID }
            }
        }
    }
    
    func didReceiveInvitation(from peerID: MCPeerID, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations for simplicity.
        invitationHandler(true, multipeerSession?.session)
    }
    
    func foundPeer(peerID: MCPeerID, sessionID: String, sessionName: String) {
        DispatchQueue.main.async {
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
