// The actual entrypoint for the app

import SwiftUI

@main
struct XRAnatomyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            XRAnatomyView()  // <-- the first view that loads. Think of this as the real entrypoint of the app.
        }
    }
}
