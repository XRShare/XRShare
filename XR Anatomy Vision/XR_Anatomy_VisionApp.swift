//MultipeerTest
import SwiftUI

@main
struct EntryPoint: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }

        ImmersiveSpace(id: "ARView") {
            ImmersiveSpaceView()
        }
    }
}
