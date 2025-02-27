import SwiftUI

@main
struct XRAnatomy_visionOSApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var arViewModel = ARViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appModel)
                .environmentObject(arViewModel)
        }
        .windowStyle(.volumetric)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            InSession()
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
