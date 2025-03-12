import SwiftUI

struct MainMenu: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    
    @State private var isJoiningSession = false
    @State private var isEnteringSessionName = false
    @State private var sessionNameInput = ""
    
    let bgColor = Color(red: 0.9137, green: 0.9176, blue: 0.9255)
    let pressedButtonColor = Color(red: 0.8, green: 0.8, blue: 0.8)
    
    var body: some View {
        ZStack {
            bgColor.ignoresSafeArea()
            
            VStack(spacing: 20) {
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
                    
                    List(arViewModel.availableSessions, id: \.self) { session in
                        Button {
                            arViewModel.multipeerSession?.invitePeer(session.peerID)
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
                    ForEach(["Host session", "Join session", "Open session"], id: \.self) { title in
                        Button {
                            switch title {
                            case "Host session":
                                isEnteringSessionName = true
                            case "Join session":
                                arViewModel.userRole = .viewer
                                arViewModel.startMultipeerServices()
                                isJoiningSession = true
                            case "Open session":
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
