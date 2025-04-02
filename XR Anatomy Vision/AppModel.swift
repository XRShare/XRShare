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
    @Published var selectedCategory: ModelCategory? = nil
    
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
                // Post notification immediately to open the window
                // Ensure this runs on the main thread if called from background
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Notification.Name("openWindow"),
                        object: nil,
                        userInfo: ["id": "controlPanel"]
                    )
                    print("Posted notification to open controlPanel")
                }
            }
        } else if !debugModeEnabled && wasEnabled {
            // When disabling debug mode, mark panel as closed
            // Note: We don't automatically close the window, just update the state.
            // The user needs to close the window manually.
            controlPanelVisible = false
            print("Debug mode disabled, control panel marked as closed (user must close window manually).")
        }
    }
    
    // Close any open panels and clean up
    func closeAllPanels() {
        controlPanelVisible = false
        // No direct way to close windows, but we mark them as closed
        print("Marked all panels as closed")
    }
}
