import SwiftUI
import MultipeerConnectivity

// MARK: - Session navigation enums

enum SessionPage {
    case mainMenu
    case modelSelection
}

enum ImmersiveSpaceState {
    case closed, inTransition, open
}

// MARK: - AppModel

@MainActor
final class AppModel: ObservableObject {
    // Navigation / state
    @Published var currentPage: SessionPage = .mainMenu
    @Published var immersiveSpaceState: ImmersiveSpaceState = .open
    @Published var selectedCategory: ModelCategory? = nil

    // Debug / panels
    @Published var debugModeEnabled = false
    @Published var controlPanelVisible = false

    // Nearby sessions (device-to-device)
    @Published var availableSessions: [(peerID: MCPeerID, sessionName: String)] = []

    // Session identity
    var sessionID: String = ""
    var sessionName: String = ""
//    var userRole: UserRole = .openSession

    // IDs used by visionOS windows / spaces
    let immersiveSpaceID = "ImmersiveSpace"
    let detailViewID = "DetailViewID"

    // MARK: - Hosting helpers
    func hostSession() {
        sessionID = UUID().uuidString
        if sessionName.isEmpty { sessionName = "visionOS-Hosted" }
        print("Hosting session: ID=\(sessionID), Name=\(sessionName)")
    }

    // MARK: - Joining helpers
    func joinSession() {
        print("Joining a session (browsing).")
    }

    // MARK: - Debug panel toggling
    func toggleDebugModeUI() {
        debugModeEnabled.toggle()
        print("Debug mode \(debugModeEnabled ? "enabled" : "disabled")")

        if debugModeEnabled {
            // Show panel once
            if !controlPanelVisible {
                controlPanelVisible = true
                NotificationCenter.default.post(name: Notification.Name("openWindow"),
                                                object: nil,
                                                userInfo: ["id": "controlPanel", "timestamp": Date.timeIntervalSinceReferenceDate])
            }
        } else {
            controlPanelVisible = false
            // Post notification to close the debug panel
            NotificationCenter.default.post(name: Notification.Name("closeWindow"),
                                            object: nil,
                                            userInfo: ["id": "controlPanel"])
        }
    }

    func closeAllPanels() {
        controlPanelVisible = false
    }
}
