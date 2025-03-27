import SwiftUI
import ARKit

@main
struct XRAnatomy_visionOSApp: App {
    @Environment(\.dismissWindow) var dismiss
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
        .windowResizability(.automatic)
        
        // Single unified debug/control panel
        WindowGroup(id: "controlPanel") {
            DebugControlsView(modelManager: modelManager, arViewModel: arViewModel)
                .environmentObject(appModel)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 400, height: 600)
        .windowResizability(.automatic)
        
        
        WindowGroup(id: "AddModelWindow"){
            AddModelView(modelManager: modelManager)
                .environmentObject(arViewModel)
                .environmentObject(appModel)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 400, height: 600)
        .windowResizability(.automatic)
        
        
        WindowGroup(id: "MainMenuView"){
            MainMenu()
                .environmentObject(arViewModel)
                .environmentObject(appModel)
                .onAppear {
                    dismiss(id: "InSessionView")
                    dismiss(id: "AddModelWindow")
                }
        }
        
        
        WindowGroup(id: "InSessionView"){
            ModelSelectionScreen(modelManager: modelManager)
                .environmentObject(arViewModel)
                .environmentObject(appModel)
                .onAppear {
                    dismiss(id: "MainMenuView")
                }
            
        }


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
