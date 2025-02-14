import SwiftUI

struct JoinSession: View {
    @EnvironmentObject var appModel: AppModel
    
    var body: some View {
        VStack {
            Text("Available Sessions").font(.title)
            List(appModel.availableSessions, id: \.peerID) { session in
                Button(session.sessionName) {
                    // When selecting a session, join it.
                    // (In a full implementation you might send invitations or set up additional data.)
                    appModel.currentPage = .inSession
                }
            }
            Button("Back") {
                appModel.currentPage = .mainMenu
            }
            .padding()
        }
    }
}
