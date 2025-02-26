//
//  HostEntityEditorView.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-26.
//

import SwiftUI
import RealityKit

struct HostEntityEditorView: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    @State private var showModelSelection: Bool = false

    var body: some View {
        ZStack {
            // RealityView with an editing anchor based on the head anchor.
            RealityView { content in
                // Use a head anchor so that models are positioned relative to the user.
                let editingAnchor = AnchorEntity(.head)
                // Offset the anchor forward by one meter so models appear in view.
                editingAnchor.transform.translation = [0, 0, -1]
                content.add(editingAnchor)
                
                // Add each hosted model to the anchor.
                for model in arViewModel.hostedModels {
                    if let entity = model.modelEntity {
                        // If the model has not been positioned, set its position to the origin of the editing anchor.
                        if entity.transform.translation == SIMD3<Float>(repeating: 0) {
                            entity.setPosition([0, 0, 0], relativeTo: editingAnchor)
                        }
                        editingAnchor.addChild(entity)
                    } else {
                        print("Model \(model.modelType.rawValue) has no modelEntity.")
                    }
                }
            } update: { content in
                // You can add per-frame updates here if needed.
            }
            .zIndex(0)
            .allowsHitTesting(false) // Prevent RealityView from intercepting touches.

            // Overlay controls.
            VStack {
                HStack {
                    Button("Back") {
                        withAnimation {
                            appModel.currentPage = .mainMenu
                        }
                    }
                    .buttonStyle(SpatialButtonStyle())
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            showModelSelection.toggle()
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .resizable()
                            .frame(width: 50, height: 50)
                            .foregroundColor(.green)
                    }
                }
                .padding()
                
                Spacer()
            }
            .zIndex(1)
            
            // Model selection overlay.
            if showModelSelection {
                ModelSelectionOverlay(showOverlay: $showModelSelection)
                    .transition(.move(edge: .bottom))
                    .zIndex(2)
            }
        }
        .onAppear {
            // Start hosting services if not already started.
            if arViewModel.multipeerSession == nil {
                arViewModel.userRole = .host
                arViewModel.startMultipeerServices()
            }
            // Load available models if not already loaded.
            if arViewModel.models.isEmpty {
                arViewModel.loadModels()
            }
        }
    }
}

struct ModelSelectionOverlay: View {
    @Binding var showOverlay: Bool
    @EnvironmentObject var arViewModel: ARViewModel
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select a Model")
                .font(.headline)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 15) {
                    ForEach(arViewModel.models, id: \.id) { model in
                        Button(action: {
                            // Create and add a new copy of the selected model.
                            let newModel = Model(modelType: model.modelType)
                            arViewModel.hostedModels.append(newModel)
                            withAnimation { showOverlay = false }
                        }) {
                            Text(model.modelType.rawValue.capitalized)
                                .padding()
                                .background(Color.blue.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }
            
            Button("Cancel") {
                withAnimation { showOverlay = false }
            }
            .buttonStyle(SpatialButtonStyle())
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 10)
        .frame(maxWidth: 400)
    }
}
