import SwiftUI
import MultipeerConnectivity

enum SessionPage {
    case mainMenu, joinSession, hostSession, hostEntityEditor, inSession
}

enum ImmersiveSpaceState {
    case closed, inTransition, open
}

// MARK: - AppModel
final class AppModel: ObservableObject {
    @Published var currentPage: SessionPage = .mainMenu
    @Published var immersiveSpaceState: ImmersiveSpaceState = .open
    
    // For the UI in “JoinSession”
    @Published var availableSessions: [(peerID: MCPeerID, sessionName: String)] = []
    
    // Store your AR session ID, name, role, etc.
    var sessionID: String = ""
    var sessionName: String = ""
    var userRole: UserRole = .openSession
    
    // The ID for the immersive space
    let immersiveSpaceID: String = "ImmersiveSpace"
    
    
    // MARK: - Hosting
    func hostSession() {
        // Example: set ID and name
        sessionID = UUID().uuidString
        if sessionName.isEmpty {
            sessionName = "visionOS-Hosted"
        }
        
        // Forward to ARViewModel or custom connectivity service
        // arViewModel?.startHosting(sessionID: sessionID, sessionName: sessionName)
        print("Hosting session: ID=\(sessionID), Name=\(sessionName)")
    }
    
    // MARK: - Joining
    func joinSession() {
        // Forward to ARViewModel or custom connectivity service
        // arViewModel?.startBrowsingForSessions()
        print("Joining a session (browsing).")
    }
    
    // You could add callbacks from MyCustomConnectivityService here:
    // e.g., foundPeer, lostPeer, etc., to update `availableSessions`.
    // The difference is that it’s no longer the direct MultipeerSessionDelegate.
}
 
