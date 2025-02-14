//
//  BottomSheet.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-12.
//


import SwiftUI

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

            Toggle("Plane Visualization", isOn: $arViewModel.isPlaneVisualizationEnabled)
            Toggle("Feature Points", isOn: $arViewModel.areFeaturePointsEnabled)
            Toggle("World Origin", isOn: $arViewModel.isWorldOriginEnabled)
            Toggle("Anchor Origins", isOn: $arViewModel.areAnchorOriginsEnabled)
            Toggle("Anchor Geometry", isOn: $arViewModel.isAnchorGeometryEnabled)
            Toggle("Scene Understanding", isOn: $arViewModel.isSceneUnderstandingEnabled)
                .onChange(of: arViewModel.isPlaneVisualizationEnabled) { val in
                    arViewModel.togglePlaneVisualization()
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
