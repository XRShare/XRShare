import SwiftUI
import RealityKit

/// The main SwiftUI View hosting the AR content.
struct InSession: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    
    // Add the immersive space dismiss environment value.
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    
    // MARK: - Anchors
    let headAnchor = AnchorEntity(.head)
    let modelAnchor = AnchorEntity(world: [0, 0, -1])
    
    // Keep a reference to your managers
    @StateObject private var modelManager = ModelManager()
    @StateObject private var sessionConnectivity = SessionConnectivity()
    
    // Track UI expansion
    @State private var expanded = false
    
    var body: some View {
        RealityView { content in
            // AR anchoring
            sessionConnectivity.addAnchorsIfNeeded(headAnchor: headAnchor,
                                                   modelAnchor: modelAnchor,
                                                   content: content)
        } update: { content in
            // Update placed models
            modelManager.updatePlacedModels(
                content: content,
                modelAnchor: modelAnchor,
                connectivity: sessionConnectivity,
                arViewModel: arViewModel
            )
        }
        .overlay(
            ModelSelectionView(modelManager: modelManager)
                .frame(width: 300, height: 400)
                .padding(),
            alignment: .bottomTrailing
        )
        // Gestures
        .gesture(modelManager.dragGesture)
        .gesture(modelManager.scaleGesture)
        .simultaneousGesture(modelManager.rotationGesture)
        .onAppear {
            modelManager.loadModelTypes()
        }
    }
    
    // MARK: - Session Reset Function
    private func resetSession() {
        arViewModel.stopMultipeerServices()
        modelManager.reset()
        
        headAnchor.children.removeAll()
        modelAnchor.children.removeAll()
        
        print("Session reset: Multipeer services stopped and anchors cleared.")
    }
}

// MARK: - Preview
#Preview(immersionStyle: .mixed) {
    InSession()
        .environmentObject(AppModel())
        .environmentObject(ARViewModel())
}
