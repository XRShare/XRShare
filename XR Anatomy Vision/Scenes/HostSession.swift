import SwiftUI

struct HostSession: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        VStack(spacing: 20) {
            Text("Hosting Session").font(.largeTitle)
            
            if let mpSession = arViewModel.multipeerSession {
                Text("Your PeerID: \(mpSession.myPeerID.displayName)")
            } else {
                Text("Session not started yet.")
            }
            
            Button("Open Immersive Space") {
                Task {
                    let result = await openImmersiveSpace(id: appModel.immersiveSpaceID)
                    switch result {
                    case .opened:
                        appModel.currentPage = .inSession
                    default:
                        appModel.currentPage = .mainMenu
                    }
                }
            }
            
            Button("Back") {
                appModel.currentPage = .mainMenu
            }
        }
        .padding()
        .onAppear {
            // If we haven’t started hosting yet:
            if arViewModel.multipeerSession == nil {
                arViewModel.userRole = .host
                arViewModel.startMultipeerServices()
            }
        }
    }
}
