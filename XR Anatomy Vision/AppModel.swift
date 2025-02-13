import SwiftUI
import MultipeerConnectivity

/// Tells Swift we want concurrency checks deferred,
/// but the class is an @Observable main-actor class
@preconcurrency
@Observable
//@MainActor // optional if you want everything strictly on main actor
class AppModel: MultipeerSessionDelegate {

    // MARK: - Immersive Space & Page

    let immersiveSpaceID = "ImmersiveSpace"

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    enum CurrentPage {
        case home
        case joinSession
        case hostSession
        case inSession
    }

    var currentPage: CurrentPage = .home
    var immersiveSpaceState: ImmersiveSpaceState = .open

    // MARK: - Multipeer

    /// Our custom MCSession wrapper
    var multipeerSession: MultipeerSession?

    /// Track connected peers for UI. Just a normal var because @Observable
    /// will detect changes automatically (like Swift’s new macros).
    var connectedPeers: [MCPeerID] = []

    // MARK: - Init
    init() {
        // Optionally start the session right away
        startMultipeerSession()
    }

    func startMultipeerSession() {
        guard multipeerSession == nil else { return }
        print(">>> Creating MultipeerSession in AppModel")
        let session = MultipeerSession()
        session.delegate = self
        self.multipeerSession = session
    }

    // Example broadcast method
    func broadcastTextMessage(_ message: String) {
        guard let session = multipeerSession else { return }
        let data = Data(message.utf8)
        session.sendToAllPeers(data, dataType: .textMessage)
    }

    // MARK: - MultipeerSessionDelegate Conformance

    /// Mark these methods as `nonisolated` so Swift can call them from
    /// non-actor code. Inside, we hop onto the main actor if we must mutate `self`.
    nonisolated func peerDidChangeState(peerID: MCPeerID, state: MCSessionState) {
        // Because it’s nonisolated, do main-actor changes in a Task:
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            print("peerDidChangeState: \(peerID.displayName) => \(state.rawValue)")
            switch state {
            case .connected:
                if !self.connectedPeers.contains(peerID) {
                    self.connectedPeers.append(peerID)
                }
            case .notConnected:
                if let i = self.connectedPeers.firstIndex(of: peerID) {
                    self.connectedPeers.remove(at: i)
                }
            case .connecting:
                print("Connecting to \(peerID.displayName)")
            @unknown default:
                break
            }
        }
    }

    nonisolated func didReceiveInvitation(from peerID: MCPeerID,
                                          invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Called from non-actor context, so we can't just do self.* unless we
        // do a main-actor hop if needed.
        print("Did receive invitation from \(peerID.displayName). Auto-accepting for now.")
        invitationHandler(true, multipeerSession?.session)
    }

    nonisolated func receivedData(_ data: Data, from peerID: MCPeerID) {
        Task { @MainActor [weak self] in
            guard self != nil else { return }
            guard data.count > 1 else { return }

            let dataTypeByte = data.first!
            let payload = data.advanced(by: 1)

            if let dt = DataType(rawValue: dataTypeByte) {
                switch dt {
                case .textMessage:
                    if let message = String(data: payload, encoding: .utf8) {
                        print("Received text from \(peerID.displayName): \(message)")
                    }

                case .anchor:
                    print("Received anchor data from \(peerID.displayName)")

                case .modelTransform:
                    print("Received model transform from \(peerID.displayName)")

                case .arWorldMap:
                    print("Received ARWorldMap")
                case .collaborationData:
                    print("Received collaboration data")
                case .removeAnchors:
                    print("Received removeAnchors request")
                case .anchorWithTransform:
                    print("Received anchor+transform data")
                case .permissionUpdate:
                    print("Received permission update")
                }
            } else {
                print("Received unknown dataType from \(peerID.displayName)")
            }
        }
    }
}
