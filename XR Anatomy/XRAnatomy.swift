// The actual entrypoint for the app

import SwiftUI

@main
struct XRAnatomyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var arViewModel = ARViewModel()
    
    var body: some Scene {
        WindowGroup {
            XRAnatomyView()
                .environmentObject(arViewModel)
                .onAppear {
                    // Initialize the model loading process but don't start multipeer automatically
                    arViewModel.deferMultipeerServicesUntilModelsLoad()
                    arViewModel.loadModels()
                }
        }
    }
}
