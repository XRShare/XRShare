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

    // Store placed models.
    @State private var placedModels: [Model] = []
    @State private var modelDict: [Entity: Model] = [:]
    @State private var entityInitialRotations: [Entity: simd_quatf] = [:]
    @State private var expanded = false
    @State private var modelTypes: [ModelType] = []
    
    // Use a state object for transform caching.
    @StateObject private var transformCache = TransformCache()
    
    // Create a dedicated world anchor (for immersive content).
    let modelAnchor = AnchorEntity(world: [0, 0, 0])
    
    var body: some View {
        ZStack {
            // RealityView for world content only.
            RealityView { content in
                // Add the world anchor if not already added.
                if modelAnchor.parent == nil {
                    content.add(modelAnchor)
                }
                
                // Add placed models as children of the world anchor.
                for model in placedModels {
                    guard !model.isLoading(), let entity = model.modelEntity else {
                        print("Skipping \(model.modelType.rawValue): still loading or missing entity")
                        continue
                    }
                    // Register with the sync service if needed.
                    if let customService = arViewModel.currentScene?.synchronizationService as? MyCustomConnectivityService,
                       customService.entity(for: entity.id) == nil {
                        customService.registerEntity(entity)
                    }
                    // Ensure the entity is added to the world anchor.
                    if entity.parent == nil {
                        modelAnchor.addChild(entity)
                    }
                }
            } update: { content in
                // Per-frame update: update transforms and broadcast changes.
                for model in placedModels {
                    guard let entity = model.modelEntity else {
                        print("Update: Model \(model.modelType.rawValue) entity is nil")
                        continue
                    }
                    // If entity hasn't been positioned, set a default position.
                    if entity.transform.translation == SIMD3<Float>(repeating: 0) {
                        DispatchQueue.main.async {
                            entity.setPosition([0, 0, -1], relativeTo: modelAnchor)
                            model.position = entity.position
                        }
                    }
                    // Update transform changes.
                    let currentMatrix = entity.transform.matrix
                    if let lastMatrix = transformCache.lastTransforms[entity.id] {
                        if lastMatrix != currentMatrix {
                            if let customService = arViewModel.currentScene?.synchronizationService as? MyCustomConnectivityService {
                                let localPeerPointer: __PeerIDRef = customService.__toCore(peerID: customService.localPeerIdentifier)
                                if let owner = customService.owner(of: entity) as? CustomPeerID,
                                   let localOwner = customService.__fromCore(peerID: localPeerPointer) as? CustomPeerID,
                                   owner == localOwner {
                                    broadcastTransform(entity)
                                }
                            }
                            DispatchQueue.main.async {
                                transformCache.lastTransforms[entity.id] = currentMatrix
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            transformCache.lastTransforms[entity.id] = currentMatrix
                        }
                    }
                }
            }
            // End RealityView
            
            // UI Overlays (added as SwiftUI overlays separate from world content)
            VStack {
                HStack {
                    backButtonOverlay
                    Spacer()
                    addModelButtonOverlay
                }
                .padding()
                Spacer()
            }
            
            if expanded {
                modelSelectionOverlay
                    .transition(.move(edge: .bottom))
            }
        }
        .gesture(dragGesture)
        .gesture(scaleGesture)
        .simultaneousGesture(rotationGesture)
        .onAppear {
            loadModelTypes()
        }
    }
    
    // MARK: - UI Overlays
    
    private var backButtonOverlay: some View {
        Button {
            appModel.currentPage = .mainMenu
        } label: {
            Image(systemName: "arrow.backward.circle.fill")
                .resizable()
                .frame(width: 50, height: 50)
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
                .frame(width: 50, height: 50)
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
            .font(.system(size: 25))
            .padding()
            .background(Color.black.opacity(0.7))
            .cornerRadius(12)
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Model Loading
    
    // Loads a model asynchronously using your asynchronous factory method.
    private func loadModel(for modelType: ModelType) {
        Task {
            print("Attempting to load model: \(modelType.rawValue).usdz")
            let model = await Model.load(modelType: modelType)
            if let modelEntity = model.modelEntity {
                modelDict[modelEntity] = model
                placedModels.append(model)
                
                // Set default scale (if needed) and place the model one meter in front of the world anchor.
                modelEntity.transform.translation = SIMD3<Float>(0, 0.2, 0.2)
                modelEntity.generateCollisionShapes(recursive: true)
                
                // Add the model entity to the world anchor.
                modelAnchor.addChild(modelEntity)
                
                // Register with the sync service.
                if let customService = arViewModel.currentScene?.synchronizationService as? MyCustomConnectivityService {
                    customService.registerEntity(modelEntity)
                }
                
                print("\(modelType.rawValue) chosen – model ready for placement")
                print("Placed \(modelType.rawValue) at position: \(modelEntity.transform.translation)")
                withAnimation { expanded = false }
            } else {
                print("Failed to load model entity for \(modelType.rawValue).usdz")
            }
        }
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
    
    private func loadModelTypes() {
        self.modelTypes = ModelType.allCases()
        print("Loaded model types: \(self.modelTypes.map { $0.rawValue })")
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

#Preview(immersionStyle: .mixed) {
    InSession()
        .environmentObject(AppModel())
}
