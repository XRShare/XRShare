import SwiftUI
import RealityKit
import ARKit
import Combine
import MultipeerConnectivity

final class TransformCache: ObservableObject {
    var lastTransforms: [Entity.ID: simd_float4x4] = [:]
}

struct InSession: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    
    // Add the immersive space dismiss environment value.
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    
    // Store placed models
    @State private var placedModels: [Model] = []
    @State private var modelDict: [Entity: Model] = [:]
    @State private var entityInitialRotations: [Entity: simd_quatf] = [:]
    
    @State private var expanded = false
    @State private var modelTypes: [ModelType] = []
    
    // Use a state object for transform caching
    @StateObject private var transformCache = TransformCache()
    
    // Anchors
    let headAnchor = AnchorEntity(.head)
    let modelAnchor = AnchorEntity(world: [0, 0, -1])
    
    var body: some View {
        RealityView { content, attachments in
            
            // 1. Add the HUD anchor entity (headAnchor) to the AR scene.
            if headAnchor.parent == nil {
                content.add(headAnchor)
            }
            // 2. Add the world anchor entity (modelAnchor) for placed models.
            if modelAnchor.parent == nil {
                content.add(modelAnchor)
            }
            
            // Attempt to find the “hudd” attachment entity; place it in front of user’s head.
            guard let hudEntity = attachments.entity(for: "hudd") else {
                print("HUD entity not found.")
                return
            }
            hudEntity.setPosition([0, 0.2, -1], relativeTo: headAnchor)
            if hudEntity.parent == nil {
                headAnchor.addChild(hudEntity)
            }
            
        } update: { content, attachments in
            // Per-frame update for placed models
            for model in placedModels {
                guard !model.isLoading(), let entity = model.modelEntity else {
                    continue
                }
                // If not positioned yet, place one meter out in front of the model anchor
                if entity.transform.translation == SIMD3<Float>(repeating: 0) {
                    DispatchQueue.main.async {
                        entity.setPosition([0, 0, -1], relativeTo: modelAnchor)
                        model.position = entity.position
                    }
                }
                // Ensure the entity is a child of the modelAnchor
                if entity.parent == nil {
                    modelAnchor.addChild(entity)
                    content.add(entity)
                }
                
                // Check for transform changes; broadcast if changed
                let currentMatrix = entity.transform.matrix
                if let lastMatrix = transformCache.lastTransforms[entity.id],
                   lastMatrix != currentMatrix {
                    if let customService = arViewModel.currentScene?.synchronizationService as? MyCustomConnectivityService {
                        let localPointer: __PeerIDRef = customService.__toCore(peerID: customService.localPeerIdentifier)
                        if let owner = customService.owner(of: entity) as? CustomPeerID,
                           let localOwner = customService.__fromCore(peerID: localPointer) as? CustomPeerID,
                           owner == localOwner {
                            broadcastTransform(entity)
                        }
                    }
                    DispatchQueue.main.async {
                        transformCache.lastTransforms[entity.id] = currentMatrix
                    }
                } else if transformCache.lastTransforms[entity.id] == nil {
                    // First time tracking this entity
                    DispatchQueue.main.async {
                        transformCache.lastTransforms[entity.id] = currentMatrix
                    }
                }
            }
            
        } attachments: {
            // The 3D HUD attachment
            Attachment(id: "hudd") {
                ZStack {
                    Color.clear
                    
                    // The “HUD UI”
                    VStack {
                        HStack {
                            backButtonOverlay
                            Spacer()
                            addModelButtonOverlay
                        }
                        .padding()
                        
                        Spacer()
                        
                        if expanded {
                            modelSelectionOverlay
                        }
                    }
                    .frame(width: 500, height: 500) // Adjust as desired
                }
            }
        }
        .gesture(dragGesture)
        .gesture(scaleGesture)
        .simultaneousGesture(rotationGesture)
        .onAppear {
            loadModelTypes()
        }
    }
    
    // MARK: - Buttons (in the 3D HUD)
    
    private var backButtonOverlay: some View {
        Button {
            // Reset the session, dismiss immersive space, and return to main menu.
            resetSession()
            Task { @MainActor in
                await dismissImmersiveSpace()
                appModel.currentPage = .mainMenu
            }
        } label: {
            Image(systemName: "arrow.backward.circle.fill")
                .resizable()
                .frame(width: 45, height: 45)
                .foregroundColor(.white)
                .shadow(radius: 5)
        }
    }
    
    private var addModelButtonOverlay: some View {
        Button {
            withAnimation {
                expanded.toggle()
                print("Add model button pressed, expanded is now \(expanded)")
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .resizable()
                .frame(width: 45, height: 45)
                .foregroundColor(.green)
                .shadow(radius: 5)
        }
    }
    
    private var modelSelectionOverlay: some View {
        VStack {
            DisclosureGroup("Select a Model", isExpanded: $expanded) {
                if modelTypes.isEmpty {
                    Text("No models found.").foregroundColor(.gray)
                } else {
                    ForEach(modelTypes, id: \.id) { modelType in
                        Button {
                            loadModel(for: modelType)
                        } label: {
                            Text("\(modelType.rawValue) Model")
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.blue.opacity(0.7))
                                .cornerRadius(8)
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .font(.system(size: 24))
            .padding()
            .background(Color.black.opacity(0.7))
            .cornerRadius(12)
            
            Spacer()
        }
        .padding(.top, 30)
    }
    
    // MARK: - Session Reset Function
    
    /// Resets the session by stopping multipeer services, clearing models, and removing anchored children.
    private func resetSession() {
        // Stop multipeer services
        arViewModel.stopMultipeerServices()
        
        // Clear any placed models and associated state
        placedModels.removeAll()
        modelDict.removeAll()
        
        // Remove all children from anchors
        headAnchor.children.removeAll()
        modelAnchor.children.removeAll()
        
        print("Session reset: Multipeer services stopped and anchors cleared.")
    }
    
    // MARK: - Loading Models
    
    private func loadModel(for modelType: ModelType) {
        Task {
            print("Attempting to load model: \(modelType.rawValue).usdz")
            let model = await Model.load(modelType: modelType)
            if let entity = model.modelEntity {
                modelDict[entity] = model
                placedModels.append(model)
                
                // Set a default position if not already set
                if (model.modelEntity?.position == SIMD3<Float>(repeating: 0.0)) {
                    model.modelEntity?.setPosition([0, 0, -1], relativeTo: headAnchor)
                    model.position = model.modelEntity!.position
                }
                
                // Register with the synchronization service
                if let customService = arViewModel.currentScene?.synchronizationService as? MyCustomConnectivityService {
                    customService.registerEntity(entity)
                }
                
                print("\(modelType.rawValue) chosen – model ready for placement")
                print("Placed \(modelType.rawValue) at position: \(entity.transform.translation)")
                
                withAnimation { expanded = false }
            } else {
                print("Failed to load model entity for \(modelType.rawValue).usdz")
            }
        }
    }
    
    private func loadModelTypes() {
        self.modelTypes = ModelType.allCases()
        print("Loaded model types: \(modelTypes.map { $0.rawValue })")
    }
    
    // MARK: - Gestures
    
    var dragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                print("Drag gesture changing")
                guard let model = modelDict[value.entity],
                      let parent = value.entity.parent else { return }
                let translation = value.translation3D
                let convertedTranslation = value.convert(translation, from: .local, to: parent)
                let newPosition = model.position + convertedTranslation
                value.entity.position = newPosition
            }
            .onEnded { value in
                guard let model = modelDict[value.entity] else { return }
                model.position = value.entity.position
                print("Drag gesture ended for \(value.entity.name)")
            }
    }
    
    var scaleGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.001)
            .targetedToAnyEntity()
            .onChanged { value in
                let entity = value.entity
                print("Scaling gesture started for \(entity.name)")
                guard let model = modelDict[entity] else { return }
                let magnification = Float(value.gestureValue.magnification)
                let newScale = model.scale * magnification
                entity.scale = newScale
                print("Entity scaled to \(entity.scale)")
            }
            .onEnded { value in
                guard let model = modelDict[value.entity] else { return }
                model.scale = value.entity.scale
                model.updateCollisionBox()
                print("Scaling gesture ended")
            }
    }
    
    var rotationGesture: some Gesture {
        RotateGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                let entity = value.entity
                if entityInitialRotations[entity] == nil {
                    entityInitialRotations[entity] = entity.transform.rotation
                    print("Initial rotation recorded for \(entity.name)")
                }
                if let initialRotation = entityInitialRotations[entity] {
                    let angle = Float(value.rotation.radians)
                    let targetRotation = initialRotation * simd_quatf(angle: angle, axis: [0, 0, 1])
                    let currentRotation = entity.transform.rotation
                    let newRotation = simd_slerp(currentRotation, targetRotation, 0.2)
                    entity.transform.rotation = newRotation
                    print("Entity rotated by \(value.rotation.radians) radians")
                }
            }
            .onEnded { value in
                let entity = value.entity
                entityInitialRotations.removeValue(forKey: entity)
                print("Rotation gesture ended for \(entity.name)")
            }
    }
    
    // MARK: - Broadcast Transform Updates
    
    private func broadcastTransform(_ entity: Entity) {
        let matrixArray = entity.transform.matrix.toArray()
        
        var data = Data()
        let idString = "\(entity.id)"
        if let idData = idString.data(using: .utf8) {
            var length = UInt8(idData.count)
            data.append(&length, count: 1)
            data.append(idData)
        }
        matrixArray.withUnsafeBufferPointer { buffer in
            data.append(Data(buffer: buffer))
        }
        var packet = Data([DataType.modelTransform.rawValue])
        packet.append(data)
        
        arViewModel.multipeerSession.sendToAllPeers(packet, dataType: .modelTransform)
        print("Broadcasted transform for entity \(entity.id)")
    }
}

// MARK: - Preview
#Preview(immersionStyle: .mixed) {
    InSession()
        .environmentObject(AppModel())
        .environmentObject(ARViewModel())
}
