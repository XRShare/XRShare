import SwiftUI

@main
struct XRAnatomy_visionOSApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var arViewModel = ARViewModel()  // Create ARViewModel

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .environmentObject(arViewModel)  // Inject ARViewModel here
        }
        .windowStyle(.volumetric)
        
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environmentObject(appModel)
                .environmentObject(arViewModel)  // Also inject in immersive view
                .onAppear { appModel.immersiveSpaceState = .open }
                .onDisappear { appModel.immersiveSpaceState = .closed }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
