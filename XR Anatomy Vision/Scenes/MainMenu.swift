import SwiftUI

struct MainMenu: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    
    // Add environment values to open/dismiss immersive space
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    // @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace // if needed
    
    @State private var isJoiningSession = false
    @State private var isEnteringSessionName = false
    @State private var sessionNameInput = ""
    
    let bgColor = Color(red: 0.9137, green: 0.9176, blue: 0.9255)
    let pressedButtonColor = Color(red: 0.8, green: 0.8, blue: 0.8)
    
    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Your existing "logo_white"
                Image("logo_white")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 360)
                    .padding(.top, 40)
                    .padding(.bottom, 30)
                
                Spacer()
                
                if isJoiningSession {
                    Text("Available Sessions:")
                        .font(.title2)
                        .foregroundColor(.black)
                        .padding()
                    
                    // List discovered sessions
                    List(arViewModel.availableSessions, id: \.self) { session in
                        Button {
                            // Connect to the chosen session
                            arViewModel.invitePeer(session)
                            // Once invitation is sent, hide UI and open the immersive space
                            isJoiningSession = false
                            moveToInSession()
                        } label: {
                            Text(session.sessionName)
                                .foregroundColor(.blue)
                        }
                    }
                    .listStyle(.plain)
                    .frame(maxWidth: .infinity)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        isJoiningSession = false
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundColor(.red)
                    .background(bgColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .stroke(Color.black, lineWidth: 2)
                    )
                    .padding()
                    
                } else {
                    // The three main options
                    ForEach(["Host session", "Join session", "Open session"], id: \.self) { title in
                        Button {
                            switch title {
                            case "Host session":
                                // Prompt user to enter a session name
                                isEnteringSessionName = true
                            case "Join session":
                                arViewModel.userRole = .viewer
                                arViewModel.startMultipeerServices()
                                isJoiningSession = true
                            case "Open session":
                                // “Open” meaning you broadcast publicly with a default session
                                arViewModel.userRole = .openSession
                                arViewModel.sessionName = "OpenSession"
                                arViewModel.sessionID = UUID().uuidString
                                arViewModel.startMultipeerServices()
                                moveToInSession()
                            default:
                                break
                            }
                        } label: {
                            Text(title)
                                .font(.title2)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity, minHeight: 25)
                                .padding()
                        }
                    }
                }
            }
            
            // If the user wants to host and must enter a custom session name
            if isEnteringSessionName {
                SessionNameInputAlert(
                    isPresented: $isEnteringSessionName,
                    sessionName: $sessionNameInput
                ) {
                    print("Session name entered: \(sessionNameInput)")
                    arViewModel.sessionName = sessionNameInput
                    arViewModel.userRole = .host
                    arViewModel.sessionID = UUID().uuidString
                    arViewModel.startMultipeerServices()
                    
                    // Trigger immersive space opening before transitioning
                    Task { @MainActor in
                        let res = await openImmersiveSpace(id: appModel.immersiveSpaceID)
                        switch res {
                        case .opened:
                            print("immersive space opened")
                        case .error:
                            print("error opening immersive space")
                        case .userCancelled:
                            print("user cancelled")
                        @unknown default:
                            break
                        }
                        moveToInSession()
                    }
                }
            }
        }
    }
    
    /// Moves the app to the “in session” screen.
    private func moveToInSession() {
        // Set the high-level app flow
        appModel.currentPage = .inSession
    }
}

struct MainMenu_Previews: PreviewProvider {
    static var previews: some View {
        MainMenu()
            .environmentObject(AppModel())
            .environmentObject(ARViewModel())
    }
}
