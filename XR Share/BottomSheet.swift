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

            // Image Sync Status and Button
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
                    arViewModel.triggerSync()
                }
                .buttonStyle(.bordered)
                .padding(.top, 5)


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
