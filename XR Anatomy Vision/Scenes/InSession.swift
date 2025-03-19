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
    
    // Create anchor entity at a more visible distance
    let modelAnchor = AnchorEntity(world: [0, 0, -0.5])
    
    // Create reference objects at different positions for debugging
    let referenceObjects = [
        (position: SIMD3<Float>(0.2, 0, -0.5), color: UIColor.red),
        (position: SIMD3<Float>(-0.2, 0, -0.5), color: UIColor.green),
        (position: SIMD3<Float>(0, 0.2, -0.5), color: UIColor.blue)
    ]
    
    // For debugging gesture issues
    @State private var lastGestureEvent = ""
    @State private var modelStats = ""
    @State private var showDebugInfo = true
    @State private var refreshTimer: Timer? = nil

    var body: some View {
        ZStack {
            // Main RealityView content
            RealityView { content in
                // Add visible reference spheres at different positions to confirm render space
                for (index, refObj) in referenceObjects.enumerated() {
                    let referenceSphere = ModelEntity(
                        mesh: .generateSphere(radius: 0.03),
                        materials: [SimpleMaterial(color: refObj.color, isMetallic: true)]
                    )
                    referenceSphere.position = refObj.position
                    referenceSphere.name = "ReferenceSphere\(index)"
                    referenceSphere.generateCollisionShapes(recursive: true)
                    
                    // Make sure it has collision for interaction
                    referenceSphere.collision = CollisionComponent(shapes: [.generateSphere(radius: 0.03)])
                    
                    // Add input target component for interactivity
                    referenceSphere.components.set(InputTargetComponent())
                    
                    // Add hover effect to show interactivity
                    referenceSphere.components.set(HoverEffectComponent())
                    
                    // Add directly to the content
                    content.add(referenceSphere)
                    print("Added interactive reference sphere \(index) at \(refObj.position)")
                }
                
                // Add a main reference sphere with high visibility
                let mainSphere = ModelEntity(
                    mesh: .generateSphere(radius: 0.05),
                    materials: [SimpleMaterial(color: .red, isMetallic: true)]
                )
                mainSphere.position = [0, 0, -0.5]
                mainSphere.name = "MainSphere"
                mainSphere.generateCollisionShapes(recursive: true)
                mainSphere.collision = CollisionComponent(shapes: [.generateSphere(radius: 0.05)])
                
                // Add input target component for interactivity
                mainSphere.components.set(InputTargetComponent())
                
                // Add hover effect to show interactivity
                mainSphere.components.set(HoverEffectComponent())
                
                content.add(mainSphere)
                print("Added interactive main sphere at \(mainSphere.position)")
                
                // Add model anchor
                content.add(modelAnchor)
                
                // Set up head anchor for spatial awareness
                let headAnchor = AnchorEntity(.head)
                content.add(headAnchor)
                
                sessionConnectivity.addAnchorsIfNeeded(
                    headAnchor: headAnchor,
                    modelAnchor: modelAnchor,
                    content: content
                )
                
                print("Scene initialized with reference objects and anchors")
        } update: { content in
            // Update model transforms and check for changes
            modelManager.updatePlacedModels(
                content: content,
                modelAnchor: modelAnchor,
                connectivity: sessionConnectivity,
                arViewModel: arViewModel
            )
            }
            // Use the simplest possible gesture configuration
            .gesture(modelManager.dragGesture)
            .gesture(modelManager.scaleGesture)
            .gesture(modelManager.rotationGesture)
            
            // Just a small status indicator
            Text("Models: \(modelManager.placedModels.count) | Gestures active")
                .font(.caption)
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
                .position(x: 100, y: 40)
                .opacity(0.7)
        }
        .onAppear {
            print("InSession has appeared. ModelManager has \(modelManager.placedModels.count) models loaded.")
            
            // Log all loaded model types for debugging
            print("Available model types: \(modelManager.modelTypes.map { $0.rawValue })")
            
            // Start multipeer services when the immersive space appears
            arViewModel.startMultipeerServices(modelManager: modelManager)
            
            // Set a timer to update the debug info periodically
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { timer in
                // Update status message with current time
                lastGestureEvent = "Scene active: \(Date().formatted(date: .omitted, time: .standard))"
                
                // Update model stats for UI display
                modelStats = "Models: \(modelManager.placedModels.count)"
                
                // Log model positions for debugging
                let modelInfo = modelManager.placedModels.map { model -> String in
                    if let entity = model.modelEntity {
                        return "\(model.modelType.rawValue): pos=\(entity.position), vis=\(entity.isEnabled), par=\(entity.parent != nil)"
                    } else {
                        return "\(model.modelType.rawValue): No entity"
                    }
                }.joined(separator: "\n")
                
                if !modelInfo.isEmpty {
                    print("Current models:\n\(modelInfo)")
                }
                
                // Auto-add a model if none are present after 5 seconds
                if modelManager.placedModels.isEmpty && timer.isValid && timer.fireDate.timeIntervalSinceNow > 5.0 {
                    if let firstModelType = modelManager.modelTypes.first {
                        print("Auto-adding model: \(firstModelType.rawValue)")
                        modelManager.loadModel(for: firstModelType, arViewModel: arViewModel)
                    }
                }
            }
            
            // If no models loaded, try to load one automatically for testing
            if modelManager.placedModels.isEmpty {
                if let heartType = modelManager.modelTypes.first(where: { $0.rawValue == "Heart" }) {
                    print("Auto-loading Heart model on appear")
                    modelManager.loadModel(for: heartType, arViewModel: arViewModel)
                } else if let firstModel = modelManager.modelTypes.first {
                    print("Auto-loading first available model: \(firstModel.rawValue)")
                    modelManager.loadModel(for: firstModel, arViewModel: arViewModel)
                }
            }
        }
        .onDisappear {
            // Clean up when the immersive space is dismissed
            refreshTimer?.invalidate()
            refreshTimer = nil
            
            arViewModel.stopMultipeerServices()
            modelManager.reset()
            sessionConnectivity.reset()
            Task {
                await dismissImmersiveSpace()
            }
        }
    }
}
