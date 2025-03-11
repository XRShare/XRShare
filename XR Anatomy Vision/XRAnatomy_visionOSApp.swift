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
                .onAppear {
                    appModel.immersiveSpaceState = .closed
                }
                
        }
        .windowStyle(.volumetric)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            InSession( modelManager: modelManager)
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
