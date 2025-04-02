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

            // Scene Understanding requires LiDAR and specific configuration
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                 Toggle("Scene Understanding (Mesh)", isOn: $arViewModel.isSceneUnderstandingEnabled)
                     .onChange(of: arViewModel.isSceneUnderstandingEnabled) { _, newValue in
                         // Requires re-running the session configuration
                         print("Scene Understanding toggle changed. Session reconfiguration might be needed.")
                     }
            } else {
                 Text("Scene Understanding not supported on this device.")
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
                         guard let modelManager = arViewModel.modelManager, let arView = arViewModel.arView else { return }
                         let model = await Model.load(modelType: referenceModelType, arViewModel: arViewModel)
                         if let entity = model.modelEntity {
                             // Clone it so we don't interfere with potential future managed instances
                             let clonedEntity = entity.clone(recursive: true)
                             // Add the visual model directly to the sharedAnchorEntity (which tracks the physical object)
                             // Set its transform to identity so it aligns perfectly
                             clonedEntity.transform = Transform()
                             arViewModel.sharedAnchorEntity.addChild(clonedEntity)
                             print("Loaded reference model 'model-mobile.usdz' visually onto tracked object.")
                             // DO NOT add to modelManager.placedModels or broadcast this debug model
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
