import SwiftUI
import MultipeerConnectivity

enum SessionPage {
    case mainMenu
    case modelSelection
}

enum ImmersiveSpaceState {
    case closed, inTransition, open
}

// MARK: - AppModel
final class AppModel: ObservableObject {
    @Published var currentPage: SessionPage = .mainMenu
    @Published var immersiveSpaceState: ImmersiveSpaceState = .open
    
    // Debug mode toggle
    @Published var debugModeEnabled: Bool = false
    @Published var controlPanelVisible: Bool = false
    
    // For the UI in "JoinSession"
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
    
    // MARK: - Debug Mode
    @MainActor
    func toggleDebugMode() async {
        debugModeEnabled.toggle()
        print("Debug mode \(debugModeEnabled ? "enabled" : "disabled")")
        
        // If enabling debug mode, show control panel 
        if debugModeEnabled && !controlPanelVisible {
            controlPanelVisible = true
            // Use notification instead of direct call to avoid MainActor issues
            NotificationCenter.default.post(
                name: Notification.Name("openWindow"), 
                object: nil, 
                userInfo: ["id": "controlPanel"]
            )
        }
    }
    
    // Non-async version for UI bindings 
    func toggleDebugModeUI() {
        let wasEnabled = debugModeEnabled
        debugModeEnabled.toggle()
        print("Debug mode \(debugModeEnabled ? "enabled" : "disabled")")
        
        // Manage control panel visibility
        if debugModeEnabled && !wasEnabled {
            // Only open if not already visible and newly enabled
            if !controlPanelVisible {
                controlPanelVisible = true
                
                // Wait a short delay before opening to avoid multiple panels 
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    Task { @MainActor in
                        // Use unique timestamp to avoid duplicate notifications
                        NotificationCenter.default.post(
                            name: Notification.Name("openWindow"), 
                            object: nil, 
                            userInfo: [
                                "id": "controlPanel",
                                "timestamp": Date().timeIntervalSince1970
                            ]
                        )
                    }
                }
            }
        } else if !debugModeEnabled && wasEnabled {
            // When disabling debug mode, mark panel as closed
            controlPanelVisible = false
        }
    }
    
    // Close any open panels and clean up
    func closeAllPanels() {
        controlPanelVisible = false
        // No direct way to close windows, but we mark them as closed
        print("Marked all panels as closed")
    }
}
