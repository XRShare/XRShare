import SwiftUI

struct JoinSession: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Available Sessions").font(.title)
            
            if arViewModel.availableSessions.isEmpty {
                Text("No sessions found yet.")
                    .foregroundColor(.secondary)
            } else {
                List(arViewModel.availableSessions, id: \.self) { session in
                    Button("Join \(session.sessionName)") {
                        // In iOS, you might do “invitePeer” from the host’s perspective,
                        // but if you want to do something on the viewer side,
                        // you could add logic here. For now, we just open ImmersiveSpace
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
                }
            }
            
            Button("Back") {
                appModel.currentPage = .mainMenu
            }
            .padding(.bottom, 30)
        }
        .padding()
    }
}
