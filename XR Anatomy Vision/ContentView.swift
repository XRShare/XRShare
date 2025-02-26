import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    
    var body: some View {
        switch appModel.currentPage {
        case .mainMenu:
            MainMenu()
        case .joinSession:
            JoinSession()
        case .hostSession:
            HostSession() // Legacy if needed
        case .hostEntityEditor:
            HostEntityEditorView()
        case .inSession:
            InSession() // The 3D experience
        }
    }
}
