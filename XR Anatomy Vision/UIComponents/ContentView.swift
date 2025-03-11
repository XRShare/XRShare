import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    @ObservedObject var modelManager: ModelManager
    
    var body: some View {
        switch appModel.currentPage {
        case .mainMenu:
            MainMenu()
            
        case .joinSession:
            JoinSession()
            
        case .hostSession:
            HostSession()
            
        case .hostEntityEditor:
            HostEntityEditorView()
            
        case .modelSelection:
            ModelSelectionScreen(modelManager: modelManager)
            
        case .inSession:
            VStack {
                Text("In-session is displayed in the ImmersiveSpace.")
                    .padding()
            }
        }
    }
}
