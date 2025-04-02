//
//  BottomSheet.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-12.
//
import SwiftUI
import ARKit

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
