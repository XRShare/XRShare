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
            HostSession()
        case .inSession:
            InSession() // your immersive AR view (from previous code)
        }
    }
}
