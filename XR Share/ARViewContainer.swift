import SwiftUI
import RealityKit
import ARKit

struct ARViewContainer: UIViewRepresentable {
    @EnvironmentObject var arViewModel: ARViewModel
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Enable Occlusion in RealityKit rendering
        arView.environment.sceneUnderstanding.options.insert(.occlusion)
        print("[iOS] ARView Scene Understanding Occlusion Enabled.")

        // Defer setup to avoid publishing changes during view updates
        DispatchQueue.main.async {
            arViewModel.setupARView(arView)
        }
        // Optionally add an ARCoachingOverlayView if desired:
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.goal = .anyPlane
        coachingOverlay.session = arView.session
        arView.addSubview(coachingOverlay)
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) { }
}
