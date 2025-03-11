//
//  InSession.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-03-11.
//


import SwiftUI
import RealityKit

struct InSession: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    
    @ObservedObject var modelManager: ModelManager
    @StateObject private var sessionConnectivity = SessionConnectivity()
    
    let modelAnchor = AnchorEntity(world: [0, 0, -1])

    var body: some View {
        RealityView { content in
            sessionConnectivity.addAnchorsIfNeeded(
                headAnchor: AnchorEntity(.head),
                modelAnchor: modelAnchor,
                content: content
            )
        } update: { content in
            modelManager.updatePlacedModels(
                content: content,
                modelAnchor: modelAnchor,
                connectivity: sessionConnectivity,
                arViewModel: arViewModel
            )
        }
        .gesture(modelManager.dragGesture)
        .gesture(modelManager.scaleGesture)
        .simultaneousGesture(modelManager.rotationGesture)
        .onAppear {
            print("InSession has appeared. ModelManager has \(modelManager.placedModels.count) models loaded.")
        }
        .onDisappear{
            _ = task{
                await dismissImmersiveSpace()
            }
        }
    }
}
