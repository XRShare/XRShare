import SwiftUI

struct MainMenu: View {
    @EnvironmentObject var appModel: AppModel  // Your state machine for pages
    @EnvironmentObject var arViewModel: ARViewModel  // The shared multi‐peer + model logic
    
    // The environment values for opening/dismissing ImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    
    var body: some View {
        VStack(spacing: 40) {
            Image("logo_white")
                .padding(.bottom, 30)
            
            // “Join” means user is a viewer
            Button("Join a Session") {
                arViewModel.userRole = .viewer
                arViewModel.startMultipeerServices()  // Browses for hosts
                appModel.currentPage = .joinSession
            }
            .font(.title)
            
            // “Host” means user is the advertiser
            Button("Host a Session") {
                Task {
                    arViewModel.userRole = .host
                    arViewModel.startMultipeerServices()
                    
                    // Open the ImmersiveSpace
                    let result = await openImmersiveSpace(id: appModel.immersiveSpaceID)
                    switch result {
                    case .opened:
                        appModel.currentPage = .inSession
                    case .userCancelled, .error:
                        appModel.currentPage = .mainMenu
                    @unknown default:
                        appModel.currentPage = .mainMenu
                    }
                }
            }
            .font(.title)
        }
    }
}
