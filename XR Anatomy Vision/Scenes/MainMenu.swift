import SwiftUI

struct MainMenu: View {
    @EnvironmentObject var appModel: AppModel
        @EnvironmentObject var arViewModel: ARViewModel

        var body: some View {
            VStack(spacing: 30) {
                Text("XR Anatomy")
                    .font(.largeTitle)
                    .bold()
                
                Spacer()
                
                // Button to join an existing session
                Button("Join Session") {
                    arViewModel.userRole = .viewer
                    arViewModel.startMultipeerServices()
                    withAnimation { appModel.currentPage = .joinSession }
                }
                .buttonStyle(SpatialButtonStyle())
                
                // Button to host a session
                Button("Host Session") {
                    arViewModel.userRole = .host
                    arViewModel.startMultipeerServices()
                    withAnimation { appModel.currentPage = .hostSession }
                }
                .buttonStyle(SpatialButtonStyle())
                
                // Button to open a public session
                Button("Open Session") {
                    arViewModel.userRole = .openSession
                    arViewModel.sessionName = "OpenSession"
                    arViewModel.sessionID = UUID().uuidString
                    arViewModel.startMultipeerServices()
                    withAnimation { appModel.currentPage = .inSession }
                }
                .buttonStyle(SpatialButtonStyle())
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: 400)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 10)
        }
    }

struct SpatialButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2)
            .padding()
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? Color.blue.opacity(0.7) : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .shadow(radius: 5)
    }
}
