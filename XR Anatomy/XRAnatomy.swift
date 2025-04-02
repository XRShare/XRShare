// The actual entrypoint for the app

import SwiftUI

@main
struct XRAnatomyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    // Initialize both ViewModel and ModelManager as StateObjects
    @StateObject private var arViewModel = ARViewModel()
    @StateObject private var modelManager = ModelManager() // Initialize ModelManager here
    
    var body: some Scene {
        WindowGroup {
            // Inject both into the environment
            XRAnatomyView()
                .environmentObject(arViewModel)
                .environmentObject(modelManager) // Inject ModelManager
                .onAppear {
                    // Assign ModelManager to ARViewModel
                    arViewModel.modelManager = modelManager
                    
                    // Initialize the model loading process but defer multipeer
                    arViewModel.deferMultipeerServicesUntilModelsLoad()
                    // Use Task for async loading
                    Task {
                        await arViewModel.loadModels()
                    }
                }
        }
    }
}
