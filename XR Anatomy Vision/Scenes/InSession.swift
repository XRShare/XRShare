//
//  InSession.swift
//  XR Anatomy
//
//  Created by Marko Vujic on 2024-12-11.
//

import SwiftUI
import RealityKit
import Combine

struct InSession: View {
    @EnvironmentObject var appModel: AppModel

    // State variables for tracking models and UI state
    @State private var entityInitialRotations: [Entity: simd_quatf] = [:]
    @State private var expanded = false
    @State private var placedModels: [Model] = []
    @State private var modelDict: [Entity: Model] = [:]
    @State private var selectedModelForPlacement: Model? = nil
    @State private var modelTypes: [ModelType] = []

    // Anchors used in the scene
    let headAnchor = AnchorEntity(.head)
    let modelAnchor = AnchorEntity(world: [0, 0, 0])
    
    var body: some View {
        ZStack {
            // RealityView with two closures (make and update)
            RealityView { content in
                // "Make" closure: set up initial content
                content.add(self.headAnchor)
                content.add(self.modelAnchor)
            } update: { content in
                // "Update" closure: update every frame
                for model in self.placedModels {
                    guard !model.isLoading(), let modelEntity = model.modelEntity else { continue }
                    let zeroVector = SIMD3<Float>(repeating: 0.0)
                    if modelEntity.position == zeroVector {
                        modelEntity.setPosition([0, 0, -1], relativeTo: self.headAnchor)
                        model.position = modelEntity.position
                    }
                    content.add(modelEntity)
                }
            }
            .gesture(dragGesture)
            .gesture(scaleGesture)
            .simultaneousGesture(rotationGesture)
            .onAppear {
                loadModelTypes()
            }
            // Overlay back button (top-leading)
            .overlay(backButtonOverlay, alignment: .topLeading)
            // Overlay add model button (bottom-trailing)
            .overlay(addModelButtonOverlay, alignment: .bottomTrailing)
            
            // Model selection overlay (center) appears when expanded == true
            if expanded {
                modelSelectionOverlay
                    .transition(.move(edge: .bottom))
            }
        }
    }
    
    // MARK: - Overlays
    
    private var backButtonOverlay: some View {
        Button {
            // Navigate back (e.g., set current page to mainMenu)
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
        .padding()
    }
    
    private var modelSelectionOverlay: some View {
        // This overlay appears when expanded is true.
        VStack {
            DisclosureGroup("Select a Model", isExpanded: $expanded) {
                if modelTypes.isEmpty {
                    Text("No models found.")
                        .foregroundColor(.gray)
                } else {
                    ForEach(modelTypes, id: \.id) { modelType in
                        Button {
                            Task {
                                print("Attempting to load model: \(modelType.rawValue).usdz")
                                // Call the async initializer with the correct label.
                                let model = await Model(modelType: modelType)
                                if let entity = model.modelEntity {
                                    self.modelDict[entity] = model
                                    self.selectedModelForPlacement = model
                                    self.placedModels.append(model)
                                    print("\(modelType.rawValue) chosen – model ready for placement")
                                    withAnimation { expanded = false }
                                } else {
                                    print("Failed to load model entity for \(modelType.rawValue).usdz")
                                }
                            }
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
    
    // MARK: - Gestures
    
    var dragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                print("Drag gesture changing")
                guard let model = self.modelDict[value.entity],
                      let parent = value.entity.parent else { return }
                let translation = value.translation3D
                let convertedTranslation = value.convert(translation, from: .local, to: parent)
                let newPosition = model.position + convertedTranslation
                value.entity.position = newPosition
            }
            .onEnded { value in
                guard let model = self.modelDict[value.entity] else { return }
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
                guard let model = self.modelDict[entity] else { return }
                let magnification = Float(value.gestureValue.magnification)
                let newScale = model.scale * magnification
                entity.scale = newScale
                print("Entity scaled to \(entity.scale)")
            }
            .onEnded { value in
                guard let model = self.modelDict[value.entity] else { return }
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
                if self.entityInitialRotations[entity] == nil {
                    self.entityInitialRotations[entity] = entity.transform.rotation
                    print("Initial rotation recorded for \(entity.name)")
                }
                if let initialRotation = self.entityInitialRotations[entity] {
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
                self.entityInitialRotations.removeValue(forKey: entity)
                print("Rotation gesture ended for \(entity.name)")
            }
    }
    
    private func loadModelTypes() {
        self.modelTypes = ModelType.allCases()
        print("Loaded model types: \(self.modelTypes.map { $0.rawValue })")
    }
}

#Preview(immersionStyle: .mixed) {
    InSession()
        .environmentObject(AppModel())
}
