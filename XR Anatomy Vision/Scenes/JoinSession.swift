import SwiftUI

struct JoinSession: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    var body: some View {
        VStack(spacing: 20) {
            Text("Available Sessions")
                .font(.title)
                .bold()
            
            if arViewModel.availableSessions.isEmpty {
                Text("No sessions found yet.")
                    .foregroundColor(.gray)
            } else {
                ScrollView {
                    VStack(spacing: 15) {
                        ForEach(arViewModel.availableSessions, id: \.self) { session in
                            Button {
                                // Example: Attempt to join the session.
                                Task {
                                    let result = await openImmersiveSpace(id: appModel.immersiveSpaceID)
                                    if result == .opened {
                                        withAnimation { appModel.currentPage = .inSession }
                                    } else {
                                        withAnimation { appModel.currentPage = .mainMenu }
                                    }
                                }
                            } label: {
                                Text(session.sessionName)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue.opacity(0.8))
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding()
                }
                .frame(maxWidth: 400)
            }
            
            Button("Back") {
                withAnimation { appModel.currentPage = .mainMenu }
            }
            .buttonStyle(SpatialButtonStyle())
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 10)
        .frame(maxWidth: 400)
    }
}
