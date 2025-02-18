import SwiftUI

struct StartupMenuView: View {
    @Binding var hasSelectedMode: Bool
    @EnvironmentObject var arViewModel: ARViewModel
    
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
                    
                    // Display discovered sessions in a list
                    List(arViewModel.availableSessions, id: \.self) { session in
                        Button(action: {
                            arViewModel.invitePeer(session)
                            // Optionally navigate away once invitation is sent:
                            isJoiningSession = false
                            hasSelectedMode = true
                        }) {
                            Text(session.sessionName)
                                .foregroundColor(.blue)
                        }
                    }
                    .listStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding()
                    
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
                    // Updated to include "Open session"
                    ForEach(["Host session", "Join session", "Open session"], id: \.self) { title in
                        Button(action: {
                            switch title {
                            case "Host session":
                                isEnteringSessionName = true  // show the text input for session name
                            case "Join session":
                                arViewModel.userRole = .viewer
                                arViewModel.startMultipeerServices()
                                isJoiningSession = true
                            case "Open session":
                                // "Open" means we broadcast publicly with some default session name
                                arViewModel.userRole = .openSession
                                arViewModel.sessionName = "OpenSession"
                                arViewModel.sessionID = UUID().uuidString
                                arViewModel.startMultipeerServices()
                                hasSelectedMode = true
                            default:
                                break
                            }
                        }) {
                            Text(title)
                                .font(.title2)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity, minHeight: 25)
                                .padding()
                        }
                        .buttonStyle(PressableButtonStyle(normalColor: bgColor,
                                                          pressedColor: pressedButtonColor))
                    }
                }
            }
            
            // If the user wants to host and needs a custom session name
            if isEnteringSessionName {
                SessionNameInputAlert(
                    isPresented: $isEnteringSessionName,
                    sessionName: $sessionNameInput
                ) {
                    // Once the user enters a name and continues:
                    arViewModel.sessionName = sessionNameInput
                    arViewModel.userRole = .host
                    arViewModel.sessionID = UUID().uuidString
                    arViewModel.startMultipeerServices()
                    hasSelectedMode = true
                }
            }
        }
        .onAppear {
            OrientationManager.shared.lock(to: .portrait)
        }
        .onDisappear {
            OrientationManager.shared.unlock()
        }
    }
}

// MARK: - Custom Button Style

struct PressableButtonStyle: ButtonStyle {
    let normalColor: Color
    let pressedColor: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? pressedColor : normalColor)
            .cornerRadius(9)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.black, lineWidth: 2))
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - SessionNameInputAlert

struct SessionNameInputAlert: View {
    @Binding var isPresented: Bool
    @Binding var sessionName: String
    var onContinue: () -> Void
    
    @FocusState private var focused: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            VStack(spacing: 16) {
                Text("Enter Session Name")
                    .font(.headline)
                    .padding(.top, 16)
                
                TextField("Session Name", text: $sessionName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .focused($focused)
                    .submitLabel(.done)
                
                Divider()
                
                HStack {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundColor(.red)
                    .padding()
                    
                    Button("Continue") {
                        isPresented = false
                        onContinue()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .disabled(sessionName.isEmpty)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 20)
            .frame(maxWidth: 300)
            .onAppear {
                focused = true
            }
        }
    }
}

// MARK: - Preview

struct StartupMenuView_Previews: PreviewProvider {
    static var previews: some View {
        StartupMenuView(hasSelectedMode: .constant(false))
            .environmentObject(ARViewModel())
    }
}
