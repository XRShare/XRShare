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
            // Set up initial scene content
            content.add(modelAnchor)
            
            // Set up head anchor for spatial awareness
            let headAnchor = AnchorEntity(.head)
            content.add(headAnchor)
            
            // Removed invalid cast to RealityKit.Scene.
            // RealityViewContent is not a RealityKit.Scene, so we no longer set the current scene.
            
            sessionConnectivity.addAnchorsIfNeeded(
                headAnchor: headAnchor,
                modelAnchor: modelAnchor,
                content: content
            )
        } update: { content in
            // Update model transforms and check for changes
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
            // Start multipeer services when the immersive space appears
            arViewModel.startMultipeerServices(modelManager: modelManager)
        }
        .onDisappear {
            // Clean up when the immersive space is dismissed
            arViewModel.stopMultipeerServices()
            modelManager.reset()
            sessionConnectivity.reset()
            Task {
                await dismissImmersiveSpace()
            }
        }
    }
}
