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
    let detailViewID: String = "DetailViewID"
    
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
        debugModeEnabled.toggle() // Toggle the state first
        print("Debug mode \(debugModeEnabled ? "enabled" : "disabled")")

        if debugModeEnabled { // If we are enabling debug mode
            // Only post notification if the panel isn't already marked as visible
            if !controlPanelVisible {
                controlPanelVisible = true // Mark as visible *before* posting
                // Post synchronously on the main thread
                NotificationCenter.default.post(
                    name: Notification.Name("openWindow"),
                    object: nil,
                    userInfo: ["id": "controlPanel", "timestamp": Date().timeIntervalSince1970] // Add timestamp
                )
                print("Posted notification synchronously to open controlPanel")
            } else {
                 print("Debug mode enabled, but controlPanelVisible was already true. No notification posted.")
            }
        } else { // If we are disabling debug mode
            // Mark the panel state as closed. User closes the window manually.
            controlPanelVisible = false
            print("Debug mode disabled, control panel state marked as closed.")
            // Do NOT post a notification to close the window.
        }
    }

    // Close any open panels and clean up
    func closeAllPanels() {
        controlPanelVisible = false
        // No direct way to close windows, but we mark them as closed
        print("Marked all panels as closed")
    }
}
