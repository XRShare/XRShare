import SwiftUI
import RealityKit
import ARKit

struct ARViewContainer: UIViewRepresentable {
    @EnvironmentObject var arViewModel: ARViewModel
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arViewModel.setupARView(arView)
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
