//
//  BottomSheet.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-12.
//
import SwiftUI
import ARKit
import RealityFoundation

struct BottomSheet<Content: View>: View {
    var content: Content
    private let heightFraction: CGFloat = 0.67

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            VStack {
                Spacer()
                VStack { content }
                .frame(width: geo.size.width, height: geo.size.height * heightFraction)
                .background(Color(.systemBackground).opacity(0.7))
                .cornerRadius(16)
                .shadow(radius: 8)
            }
            .edgesIgnoringSafeArea(.bottom)
        }
    }
}

struct SettingsView: View {
    @Binding var isVisible: Bool
    @ObservedObject var arViewModel: ARViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings").font(.headline).padding(.top)

            #if os(iOS) // These toggles are specific to iOS ARKit debug options
            Toggle("Plane Visualization", isOn: $arViewModel.isPlaneVisualizationEnabled)
                .onChange(of: arViewModel.isPlaneVisualizationEnabled) { _, newValue in
                    if newValue {
                        arViewModel.arView?.debugOptions.insert(.showPhysics) // Use insert for sets
                    } else {
                        arViewModel.arView?.debugOptions.remove(.showPhysics) // Use remove for sets
                    }
                }
            Toggle("Feature Points", isOn: $arViewModel.areFeaturePointsEnabled)
                 .onChange(of: arViewModel.areFeaturePointsEnabled) { _, newValue in
                     if newValue {
                         arViewModel.arView?.debugOptions.insert(.showFeaturePoints)
                     } else {
                         arViewModel.arView?.debugOptions.remove(.showFeaturePoints)
                     }
                 }
            Toggle("World Origin", isOn: $arViewModel.isWorldOriginEnabled)
                 .onChange(of: arViewModel.isWorldOriginEnabled) { _, newValue in
                     if newValue {
                         arViewModel.arView?.debugOptions.insert(.showWorldOrigin)
                     } else {
                         arViewModel.arView?.debugOptions.remove(.showWorldOrigin)
                     }
                 }
            // Anchor debug options might require more complex handling or might not be standard debugOptions
            // Toggle("Anchor Origins", isOn: $arViewModel.areAnchorOriginsEnabled)
            // Toggle("Anchor Geometry", isOn: $arViewModel.isAnchorGeometryEnabled)

            // Scene Understanding / Occlusion Toggle
            // Note: This toggle is illustrative. Enabling/disabling requires session reconfiguration.
            // We check for person segmentation support, which is key for hand occlusion.
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
                 Toggle("Person Occlusion", isOn: $arViewModel.isSceneUnderstandingEnabled)
                     .onChange(of: arViewModel.isSceneUnderstandingEnabled) { _, newValue in
                         // Requires re-running the session configuration to actually change frameSemantics
                         print("Person Occlusion toggle changed to \(newValue). Session reconfiguration needed to apply.")
                         // Trigger reconfiguration
                         Task { @MainActor in
                             arViewModel.reconfigureARSession()
                         }
                         // Update ARView option immediately (though session needs restart)
                         if newValue {
                             arViewModel.arView?.environment.sceneUnderstanding.options.insert(.occlusion)
                         } else {
                             arViewModel.arView?.environment.sceneUnderstanding.options.remove(.occlusion)
                         }
                     }
                     .onAppear {
                         // Sync toggle state with current ARView state on appear
                         arViewModel.isSceneUnderstandingEnabled = arViewModel.arView?.environment.sceneUnderstanding.options.contains(.occlusion) ?? false
                     }
            } else {
                 Text("Person Occlusion not supported on this device.")
                     .font(.caption)
                     .foregroundColor(.secondary)
            }
            #else
             Text("Debug options not applicable on this platform.")
                 .font(.caption)
                 .foregroundColor(.secondary)
            #endif

            // Sync Mode Picker (Example - Adapt as needed for iOS UI)
            Picker("Sync Mode", selection: $arViewModel.currentSyncMode) {
                ForEach(SyncMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: arViewModel.currentSyncMode) { _, newMode in
                print("iOS Sync Mode changed to: \(newMode.rawValue)")
                // Trigger session reconfiguration when the mode changes
                Task { @MainActor in
                    arViewModel.reconfigureARSession()
                }
                // Reset sync state immediately (reconfigureARSession also does this, but good for immediate UI feedback)
                arViewModel.isSyncedToImage = false
                arViewModel.isImageTracked = false
            }

            // Image Sync Status and Button
            if arViewModel.currentSyncMode == .imageTarget {
                HStack {
                    Circle()
                        .fill(arViewModel.isImageTracked ? Color.green : (arViewModel.isSyncedToImage ? Color.blue : Color.red))
                        .frame(width: 10, height: 10)

                    if arViewModel.isSyncedToImage {
                        Text(arViewModel.isImageTracked ? "Image Detected (Synced)" : "Synced via Image (Not Detected)")
                            .font(.caption)
                    } else {
                        Text(arViewModel.isImageTracked ? "Image Detected (Syncing...)" : "Awaiting Image Sync...")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                Button("Re-Sync Image") {
                    arViewModel.triggerImageSync()
                }
                .buttonStyle(.bordered)
                .disabled(arViewModel.currentSyncMode != .imageTarget)
                .padding(.top, 5)
            }
            // Object Sync Status and Button
            else if arViewModel.currentSyncMode == .objectTarget {
                 HStack {
                     Circle()
                         .fill(arViewModel.isObjectTracked ? Color.green : (arViewModel.isSyncedToObject ? Color.blue : Color.red))
                         .frame(width: 10, height: 10)

                     if arViewModel.isSyncedToObject {
                         Text(arViewModel.isObjectTracked ? "Object Detected (Synced)" : "Synced via Object (Not Detected)")
                             .font(.caption)
                     } else {
                         Text(arViewModel.isObjectTracked ? "Object Detected (Syncing...)" : "Awaiting Object Sync...")
                             .font(.caption)
                             .foregroundColor(.orange)
                     }
                 }
                 Button("Re-Sync Object") {
                     arViewModel.triggerImageSync() // Reusing triggerImageSync which now handles object mode too
                 }
                 .buttonStyle(.bordered)
                 .disabled(arViewModel.currentSyncMode != .objectTarget)
                 .padding(.top, 5)

                 // Debug button to load the reference object's model
                 Button("Load Reference Model") {
                     // Define the model type for the reference object model
                     let referenceModelType = ModelType(rawValue: "model-mobile") // Ensure this USDZ exists

                     // Load the model locally without broadcasting
                     Task { @MainActor in
                         guard let modelManager = arViewModel.modelManager,
                               let customService = arViewModel.customService,
                               let arView = arViewModel.arView else {
                             print("Error: ModelManager, CustomService, or ARView not available for reference model loading.")
                             return
                         }
                         // Load the model template
                         let modelTemplate = await Model.load(modelType: referenceModelType, arViewModel: arViewModel)

                         if let entityTemplate = modelTemplate.modelEntity {
                             // Clone the entity for placement
                             let clonedEntity = entityTemplate.clone(recursive: true)
                             clonedEntity.name = "ReferenceObjectModel_Debug" // Give it a specific name
                             clonedEntity.transform = Transform() // Align at origin of the shared anchor

                             // Assign a unique instance ID if needed
                             if clonedEntity.components[InstanceIDComponent.self] == nil {
                                 clonedEntity.components.set(InstanceIDComponent())
                             }
                             let instanceID = clonedEntity.components[InstanceIDComponent.self]!.id

                             // Add to the shared anchor (which tracks the physical object)
                             // Ensure shared anchor is in the scene first
                             if arViewModel.sharedAnchorEntity.scene == nil {
                                 arView.scene.addAnchor(arViewModel.sharedAnchorEntity)
                                 print("[iOS] Added sharedAnchorEntity to scene before adding reference model.")
                             }
                             arViewModel.sharedAnchorEntity.addChild(clonedEntity)

                             // Create a new Model instance specifically for this placed debug entity
                             let placedDebugModel = Model(modelType: referenceModelType, arViewModel: arViewModel)
                             placedDebugModel.modelEntity = clonedEntity // Assign the cloned entity
                             placedDebugModel.loadingState = .loaded // Mark as loaded

                             // Register with ModelManager for gesture handling
                             modelManager.modelDict[clonedEntity] = placedDebugModel
                             modelManager.placedModels.append(placedDebugModel) // Add to placed models list

                             // Register with ConnectivityService as locally owned, DO NOT BROADCAST ADD
                             customService.registerEntity(clonedEntity, modelType: referenceModelType, ownedByLocalPeer: true)

                             print("[iOS] Loaded and registered interactive reference model 'model-mobile.usdz' (InstanceID: \(instanceID)) onto tracked object.")

                         } else {
                             arViewModel.alertItem = AlertItem(title: "Load Failed", message: "Could not load 'model-mobile.usdz'.")
                         }
                     }
                 }
                 .buttonStyle(.bordered)
                 .tint(.purple)
                 .disabled(!arViewModel.isSyncedToObject) // Only enable after initial sync
                 .padding(.top, 5)
            }


            Spacer()
            Button("Close") {
                isVisible = false
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(8)
            .padding(.horizontal)
        }
        .padding()
    }
}
