import SwiftUI
import RealityKit
import ARKit

struct ARViewContainer: UIViewRepresentable {
    @EnvironmentObject var arViewModel: ARViewModel
    var onSwipeFromLeftEdge: (() -> Void)?  // to detect a left-edge swipe gesture

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arViewModel.arView = arView
        arViewModel.setupARView(arView)
        addCoachingOverlay(to: arView)
        addEdgePanGestureRecognizer(to: arView, context: context)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) { }

    private func addCoachingOverlay(to arView: ARView) {
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        coachingOverlay.goal = .anyPlane
        coachingOverlay.session = arView.session
        arView.addSubview(coachingOverlay)
    }

    private func addEdgePanGestureRecognizer(to arView: ARView, context: Context) {
        let edgePanGesture = UIScreenEdgePanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleEdgePan(_:))
        )
        edgePanGesture.edges = .left
        arView.addGestureRecognizer(edgePanGesture)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: ARViewContainer

        init(_ parent: ARViewContainer) {
            self.parent = parent
        }

        @objc func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
            if gesture.state == .recognized {
                parent.onSwipeFromLeftEdge?()
            }
        }
    }
}
