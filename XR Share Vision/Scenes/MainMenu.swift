import SwiftUI

struct MainMenu: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    
    @Environment(\.openWindow) private var openWindow
    
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    
    @State private var isJoiningSession = false
    @State private var isEnteringSessionName = false
    @State private var sessionNameInput = ""
    
    let bgColor = Color(red: 0.9137, green: 0.9176, blue: 0.9255)
    let pressedButtonColor = Color(red: 0.8, green: 0.8, blue: 0.8)
    
    var body: some View {
        ZStack {
            
            VStack(spacing: 20) {
               
                Text("XRShare")
                    .padding()
                    .font(.largeTitle)
                
            
                if isJoiningSession {
                    
                    
                    VStack(spacing: 20) {
                        
                        Text("Available Sessions:")
                            .font(.title2)
                            .foregroundColor(.black)
                            .padding()
                            
                        
                        
                        List(arViewModel.availableSessions, id: \.self) { session in
                            Button {
                                arViewModel.invitePeer(session)
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
                        .foregroundColor(.red)
                        .padding()
                        
                    }
                    .frame(maxWidth: 600, minHeight: 270)
                    .cornerRadius(30)
                    .padding()
                    
                    
                    
                    
                    
                } else {
                    ForEach(["Host session", "Join session", "Local session"], id: \.self) { title in
                        Button {
                            switch title {
                            case "Host session":
                                isEnteringSessionName = true
                            case "Join session":
                                arViewModel.userRole = .viewer
                                arViewModel.startMultipeerServices()
                                isJoiningSession = true
                            case "Local session":
                                arViewModel.userRole = .localSession
                                arViewModel.sessionName = "LocalSession"
                                arViewModel.sessionID = UUID().uuidString
                                // Don't start multipeer services for local mode
                                moveToInSession()
                            default:
                                break
                            }
                        } label: {
                            Text(title)
                                .font(.title2)
                                .fontWeight(.bold)
                                .frame(maxWidth: 400, minHeight: 25)
                                .padding()
                        }
                    }
                }
            }
            
            // Session name input overlay
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
                    
                    Task { @MainActor in
                        moveToInSession()
                    }
                }
            }
        }
    }
  
    
    private func moveToInSession() {
        appModel.currentPage = .modelSelection
    }
}

struct MainMenu_Previews: PreviewProvider {
    static var previews: some View {
        MainMenu()
            .environmentObject(AppModel())
            .environmentObject(ARViewModel())
    }
}
