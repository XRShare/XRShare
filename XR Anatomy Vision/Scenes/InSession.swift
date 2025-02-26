import SwiftUI
import RealityKit
import MultipeerConnectivity

struct InSession: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    
    // Access the underlying RealityKit scene.
    @Environment(\.realityKitScene) var scene: RealityKit.Scene?
    
    // Store placed models.
    @State private var placedModels: [Model] = []
    @State private var modelDict: [Entity: Model] = [:]
    @State private var entityInitialRotations: [Entity: simd_quatf] = [:]
    @State private var expanded = false  // For UI toggles.
    @State private var modelTypes: [ModelType] = []
    
    // Track last known transforms (keyed by Entity.ID).
    @State private var lastTransforms: [Entity.ID: simd_float4x4] = [:]
    
    // Anchors for the scene.
    let headAnchor = AnchorEntity(.head)
    let modelAnchor = AnchorEntity(world: .zero)
    
    var body: some View {
        ZStack {
            RealityView { content in
                // Add anchors.
                content.add(headAnchor)
                content.add(modelAnchor)
                
                // For each placed model, register its entity (if not already registered) and add it.
                for model in placedModels {
                    guard !model.isLoading(), let entity = model.modelEntity else { continue }
                    if let customService = scene?.synchronizationService as? MyCustomConnectivityService,
                       customService.entity(for: entity.id) == nil {
                        // The service internally sets the owner.
                        customService.registerEntity(entity)
                    }
                    content.add(entity)
                }
            } update: { content in
                // For every placed model, check if its transform has changed.
                for model in placedModels {
                    guard let entity = model.modelEntity else { continue }
                    let currentMatrix = entity.transform.matrix
                    if let lastMatrix = lastTransforms[entity.id] {
                        if lastMatrix != currentMatrix {
                            // Broadcast transform update only if the local device owns this entity.
                            if let customService = scene?.synchronizationService as? MyCustomConnectivityService {
                                let localPeerPointer: __PeerIDRef = customService.__toCore(peerID: customService.localPeerIdentifier)
                                if let owner = customService.owner(of: entity) as? CustomPeerID,
                                   let localOwner = customService.__fromCore(peerID: localPeerPointer) as? CustomPeerID,
                                   owner == localOwner {
                                    broadcastTransform(entity)
                                }
                            }
                            lastTransforms[entity.id] = currentMatrix
                        }
                    } else {
                        lastTransforms[entity.id] = currentMatrix
                    }
                }
            }
            // End RealityView.
            .overlay(backButtonOverlay, alignment: .topLeading)
            .overlay(addModelButtonOverlay, alignment: .bottomTrailing)
            
            if expanded {
                modelSelectionOverlay
                    .transition(.move(edge: .bottom))
            }
        }
        .onAppear {
            if let mpSession = arViewModel.multipeerSession {
                do {
                    // Instantiate the custom connectivity service.
                    let syncService = try MyCustomConnectivityService(session: mpSession.session)
                    // Optionally set ARSession.delegate = syncService if needed.
                    scene?.synchronizationService = syncService
                } catch {
                    print("Custom sync service creation failed: \(error)")
                }
            }
            // Save the current scene in the view model.
            arViewModel.currentScene = scene
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
        .padding()
    }
    
    private var addModelButtonOverlay: some View {
        Button {
            withAnimation { expanded.toggle() }
        } label: {
            Image(systemName: "plus.circle.fill")
                .resizable()
                .frame(width: 50, height: 50)
                .foregroundColor(.green)
                .shadow(radius: 5)
        }
        .padding()
    }
    
    private var modelSelectionOverlay: some View {
        VStack {
            DisclosureGroup("Select a Model", isExpanded: $expanded) {
                if modelTypes.isEmpty {
                    Text("No models found.").foregroundColor(.gray)
                } else {
                    ForEach(modelTypes, id: \.id) { modelType in
                        Button(modelType.rawValue) {
                            Task {
                                let model = Model(modelType: modelType)
                                if let entity = model.modelEntity {
                                    placedModels.append(model)
                                    modelDict[entity] = model
                                    
                                    entity.transform.translation = SIMD3<Float>(0, 0, -1)
                                    entity.generateCollisionShapes(recursive: true)
                                    
                                    // Register the new entity with the sync service.
                                    if let customService = scene?.synchronizationService as? MyCustomConnectivityService {
                                        customService.registerEntity(entity)
                                    }
                                    
                                    withAnimation { expanded = false }
                                }
                            }
                        }
                        .font(.headline)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.blue.opacity(0.7))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                }
            }
            .font(.title3)
            .padding()
            .background(Color.black.opacity(0.7))
            .cornerRadius(12)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Broadcast Transform Updates
    private func broadcastTransform(_ entity: Entity) {
        let matrixArray = entity.transform.matrix.toArray()
        var data = Data()
        // Serialize the entity's ID by converting it to a string.
        let idString = "\(entity.id)"
        if let idData = idString.data(using: .utf8) {
            // Write the length (assumed to fit in one byte).
            var length = UInt8(idData.count)
            data.append(&length, count: 1)
            data.append(idData)
        }
        // Append the 16 floats representing the 4x4 matrix.
        matrixArray.withUnsafeBufferPointer { buffer in
            data.append(Data(buffer: buffer))
        }
        // Prepend the data type byte.
        var packet = Data([DataType.modelTransform.rawValue])
        packet.append(data)
        
        arViewModel.multipeerSession.sendToAllPeers(packet, dataType: .modelTransform)
        print("Broadcasted transform for entity \(entity.id)")
    }
}
