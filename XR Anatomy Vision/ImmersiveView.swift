import SwiftUI
import RealityKit

struct ImmersiveView: View {
    var body: some View {
        RealityView { content in
            // Load your shared scene (for example from Reality Composer)
            if let scene = try? await Entity.loadAnchor(named: "SharedScene", in: .main) {
                content.add(scene)
            }
        } update: { content in
            // Optional: update the scene as needed
        }
    }
}
