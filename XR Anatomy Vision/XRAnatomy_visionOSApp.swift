import SwiftUI

@main
struct XRAnatomy_visionOSApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var arViewModel = ARViewModel()

    var body: some Scene {
        WindowGroup {
            // Fallback content if needed; primary navigation is within immersive space.
            ContentView()
                .environmentObject(appModel)
                .environmentObject(arViewModel)
        }
        .windowStyle(.volumetric)
        
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ZStack {
                // The immersive AR/RealityKit content.
                ImmersiveView()
                    .environmentObject(appModel)
                    .environmentObject(arViewModel)
                    .onAppear { appModel.immersiveSpaceState = .open }
                    .onDisappear { appModel.immersiveSpaceState = .closed }
                
                // Show the spatial main menu only when the app is in main menu mode.
                if appModel.currentPage == .mainMenu {
                    MainMenu()
                        .transition(.opacity)
                }
            }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
