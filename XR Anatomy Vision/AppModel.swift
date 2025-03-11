import SwiftUI
import MultipeerConnectivity

enum SessionPage {
    case mainMenu
    case joinSession
    case hostSession
    case hostEntityEditor
    case modelSelection
    case inSession
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
    
    // Store your AR session info
    var sessionID: String = ""
    var sessionName: String = ""
    var userRole: UserRole = .openSession
    
    // The ID for the immersive space
    let immersiveSpaceID: String = "ImmersiveSpace"
    
    // MARK: - Hosting
    func hostSession() {
        sessionID = UUID().uuidString
        if sessionName.isEmpty {
            sessionName = "visionOS-Hosted"
        }
        print("Hosting session: ID=\(sessionID), Name=\(sessionName)")
    }
    
    // MARK: - Joining
    func joinSession() {
        print("Joining a session (browsing).")
    }
}
