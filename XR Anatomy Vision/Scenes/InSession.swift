//
//  InSession.swift
//  XR Anatomy
//
//  Created by Marko Vujic on 2024-12-11.
//

import SwiftUI
import RealityKit
import ARKit
import Combine

struct InSession: View  {
    @State private var entityInitialRotations: [Entity: simd_quatf] = [:]
    @State private var expanded = false
    @State private var placedModels : [Model] = []
    @State private var modelDict: [Entity:Model] = [:]
    @State private var selectedModelForPlacement: Model? = nil
    @State private var modelTypes: [ModelType] = []
    let headAnchor = AnchorEntity(.head)
    let modelAnchor = AnchorEntity(world: [0,0,0])
    var body: some View {
        
        
        RealityView { content, attachments in
            guard let attachmentEntity = attachments.entity(for: "hudd") else {
                print("Hud failed to load")
                return
            }
            //content.add(attachmentEntity)
            
            //let sphere = ModelEntity(mesh: MeshResource.generateSphere(radius: 0.1), materials: [SimpleMaterial(color: .red, isMetallic: false)])
            //sphere.setPosition([0,0,-4], relativeTo: headAnchor)
            
            //headAnchor.addChild(sphere)
            
            attachmentEntity.setPosition([0,0.2,-1], relativeTo: headAnchor)
            headAnchor.addChild(attachmentEntity)
            content.add(headAnchor)
            content.add(modelAnchor)
            
            //attachmentEntity.transform.translation.y = 0.2
            //attachmentEntity.transform.translation.z = 0.1
            //attachmentEntity.position = SIMD3<Float>(0.0,-0.4,-0.25)
            
        }
        update: { content, attachments in
            for model in placedModels {
                guard !model.isLoading() else{continue}
                
                guard model.modelEntity != nil else{continue}
                if (model.modelEntity?.position == SIMD3<Float>(repeating:0.0)) {
                    model.modelEntity?.setPosition([0,0,-1], relativeTo: headAnchor)
                    model.position = model.modelEntity!.position
                }
                
                //modelAnchor.addChild(model.modelEntity!)
                content.add(model.modelEntity!)
            }
        }
        attachments: {
            
            Attachment(id:"hudd") {
                ZStack {
                    DisclosureGroup("Models", isExpanded: $expanded) {
                        if modelTypes.isEmpty {
                            Text("No models found.")
                                .foregroundColor(.gray)
                        } else {
                            ForEach(modelTypes, id: \.id) { modelType in
                                Button {
                                    Task {
                                        print("Attempting to load model: \(modelType.rawValue).usdz")
                                        let model = await Model(modelName: modelType.rawValue)
                                        if let modelEntity = model.modelEntity {
                                            modelDict[modelEntity] = model
                                            selectedModelForPlacement = model
                                            placedModels.append(model)
                                            print("\(modelType.rawValue) chosen - model ready for placement")
                                            
                                            // Collapse the menu after selecting a model
                                            expanded = false
                                            print("Models menu collapsed.")
                                        } else {
                                            print("Failed to load model entity for \(modelType.rawValue).usdz")
                                        }
                                    }
                                } label: {
                                    Text("\(modelType.rawValue) Model")
                                        .foregroundColor(.white)
                                        .padding()
                                        //.background(Color.blue.opacity(0.7))
                                        .cornerRadius(8)
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }
                    .font(.system(size: 25))
                    .padding()
                }
                .padding(.top, 250)
//                ZStack{
//                    DisclosureGroup ("Models", isExpanded: $expanded) {
//                        Button{
//                            Task {
//                                let model = await Model(modelName: "heart2K")
//                                
//                                modelDict[model.modelEntity!] = model
//                                placedModels.append(model)
//                            }
//                            print("heart chosen")
//                            
//                        } label: {
//                            Text("heart model ")
//                        }
//                        Button{
//                            Task {
//                                let model = await Model(modelName: "arteriesHead")
//                                
//                                modelDict[model.modelEntity!] = model
//                                placedModels.append(model)
//                            }
//                            print("brain arteries chosen")
//                        } label: {
//                            Text("brain arteries model")
//                        }
//                    }
//                    .font(.system(size: 35))
//                }
//                .padding(.top, 250)
                
            }
        }
        .gesture(dragGesture)
        .gesture(scaleGesture)
        .simultaneousGesture(rotationGesture)
        .onAppear {             // added this
            loadModelTypes()
        }
        
    }
    var dragGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                print("drag gesture changing")
                let model = modelDict[value.entity]!
                value.entity.position = model.position + value.convert(value.translation3D, from: .local, to: value.entity.parent!)
                
            } .onEnded{ value in
                let model = modelDict[value.entity]!
                model.position = value.entity.position
                print("translation gesture on \(value.entity.name) endend")
            }
    }
    
    var scaleGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.001)
            .targetedToAnyEntity()
            .onChanged { value in
                let entity = value.entity // Directly access the entity
                //guard initialScale != nil else {return}
                print("Scaling gesture started for entity: \(entity.name)")
                let model = modelDict[entity]!
                // Adjust the scale
                let newScale = model.scale *  Float(value.gestureValue.magnification)
                entity.scale = newScale
                // entity.position -= centroid
                
                //entity.position += centroid
                
                print("Entity scaled to: \(entity.scale)")
            }
            .onEnded { value in
                let model = modelDict[value.entity]!
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
                if entityInitialRotations[entity] == nil {
                    entityInitialRotations[entity] = entity.transform.rotation
                    print("Initial rotation recorded for entity: \(entity.name)")
                }
                if let initialRotation = entityInitialRotations[entity] {
                    // Rotate around Z-axis (wrist twist axis)
                    let targetRotation = initialRotation * simd_quatf(angle: Float(value.rotation.radians), axis: [0, 0, 1])
                    let currentRotation = entity.transform.rotation
                    let mixFactor: Float = 0.2 // Adjust for smoother rotation
                    let newRotation = simd_slerp(currentRotation, targetRotation, mixFactor)
                    
                    entity.transform.rotation = newRotation
                    print("Entity rotated by radians: \(value.rotation.radians)")
                }
            }
            .onEnded { value in
                let entity = value.entity
                entityInitialRotations.removeValue(forKey: entity)
                print("Rotation gesture ended for entity: \(entity.name)")
            }
    }
    
    private func loadModelTypes() {
        modelTypes = ModelType.allCases()
        print("Loaded model types: \(modelTypes.map { $0.rawValue })")
    }
}
#Preview(immersionStyle: .mixed) {
    InSession()
        .environment(AppModel())
}


extension ModelEntity {
    static func loadModel(named name: String) async throws -> ModelEntity {
        try await withCheckedThrowingContinuation { continuation in
            loadModelAsync(named: name)
                .sink(receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        continuation.resume(throwing: error)
                    }
                }, receiveValue: { model in
                    continuation.resume(returning: model)
                })
                .store(in: &cancellables)
        }
    }
    
    private static var cancellables = Set<AnyCancellable>()
}

// MARK: - Public Extension for float4x4

public extension float4x4 {
    var translation: SIMD3<Float> {
        [columns.3.x, columns.3.y, columns.3.z]
    }

    var matrix: float4x4 {
        self
    }
    
    var forward: SIMD3<Float> {
        let f = -columns.2
        return SIMD3<Float>(f.x, f.y, f.z)
    }
}
