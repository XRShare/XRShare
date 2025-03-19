import SwiftUI
import ARKit

@main
struct XRAnatomy_visionOSApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var arViewModel = ARViewModel()
    @StateObject private var modelManager = ModelManager()
    @State var session = ARKitSession()

    var body: some Scene {
        WindowGroup {
            ContentView(modelManager: modelManager)
                .environmentObject(appModel)
                .environmentObject(arViewModel)
                .withWindowOpener() // Add our window opener capability
                .onAppear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .windowStyle(.volumetric)
        
        // Single unified debug/control panel
        WindowGroup(id: "controlPanel") {
            DebugControlsView(modelManager: modelManager, arViewModel: arViewModel)
                .environmentObject(appModel)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 400, height: 600)
        .windowResizability(.automatic)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            InSession(modelManager: modelManager)
                .environmentObject(appModel)
                .environmentObject(arViewModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}
