import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    @ObservedObject var modelManager: ModelManager
    
    var body: some View {
        switch appModel.currentPage {
        case .mainMenu:
            MainMenu()
            
        case .modelSelection:
            ModelSelectionScreen(modelManager: modelManager)
        }
    }
}
