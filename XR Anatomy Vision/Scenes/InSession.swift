//
//  InSession.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-03-11.
//


import SwiftUI
import RealityKit
import ARKit

struct InSession: View {
    @EnvironmentObject var appModel: AppModel 
    @EnvironmentObject var arViewModel: ARViewModel
    @EnvironmentObject var appState: AppState
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Environment(\.openWindow) private var openWindow
    
    @ObservedObject var modelManager: ModelManager
    @StateObject private var sessionConnectivity = SessionConnectivity()
    
    // Passed Properties
    var session: ARKitSession // Receive the ARKitSession instance
    
    // Create anchor entity at eye level and a comfortable distance
    let modelAnchor = AnchorEntity(world: [0, 0.15, -0.5])
    
    // Reference objects only shown in debug mode
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
    @State private var timerCounter = 0

    var body: some View {
        ZStack {
            // Main RealityView content
            RealityView { content in
                // Only add reference spheres if in debug mode
                if appModel.debugModeEnabled {
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
                }
                
                // Add both anchors to the scene (guaranteed present)
                content.add(modelAnchor)
                content.add(arViewModel.sharedAnchorEntity)
                
                // Make sure they're enabled
                modelAnchor.isEnabled = true
                arViewModel.sharedAnchorEntity.isEnabled = true
                
                print("Added both world and image anchors to scene")
                
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
            // Add tap gesture first for selection, then the manipulation gestures
            .gesture(modelManager.tapGesture)
            .gesture(modelManager.dragGesture)
            .gesture(modelManager.scaleGesture)
            .gesture(modelManager.rotationGesture)
            
            // Status indicator with selection info
            VStack(alignment: .leading, spacing: 4) {
                Text("Session active: \(modelManager.placedModels.count) models")
                    .font(.caption)
                
                if let selectedID = modelManager.selectedModelID {
                    Text("Selected: \(selectedID.rawValue)")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else if !modelManager.placedModels.isEmpty {
                    Text("Tap a model to select it")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(.ultraThinMaterial)
            .cornerRadius(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .opacity(0.8)
        }
        .withWindowOpener() // Add window opening capability
        .onAppear {
            print("InSession has appeared. ModelManager has \(modelManager.placedModels.count) models loaded.")
            
            // Log all loaded model types for debugging
            print("Available model types: \(modelManager.modelTypes.map { $0.rawValue })")
            
            // Start multipeer services when the immersive space appears
            arViewModel.startMultipeerServices(modelManager: modelManager)
            
            // Debug panel managed entirely from ModelSelectionView
            // No automatic panel opening here
            
            // Timer counter is now a class property
            
            // Set a timer to update the debug info periodically
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { timer in
                // Increment the counter 
                timerCounter += 1
                
                // Update status message with current time
                lastGestureEvent = "Updated: \(Date().formatted(date: .omitted, time: .standard))"
                
                // Update model stats for UI display
                let modelCount = modelManager.placedModels.count
                modelStats = "Active models: \(modelCount)"
                
                // Log model positions for debugging, but less frequently
                Task { @MainActor in
                    if modelCount > 0 && timerCounter % 3 == 0 {  // Only log every 15 seconds
                        let modelInfo = modelManager.placedModels.map { model -> String in
                            if model.isLoaded(), let entity = model.modelEntity {
                                let pos = entity.position
                                return "\(model.modelType.rawValue): pos=(\(String(format: "%.2f", pos.x)), \(String(format: "%.2f", pos.y)), \(String(format: "%.2f", pos.z)))"
                            } else {
                                return "\(model.modelType.rawValue): No entity"
                            }
                        }.joined(separator: "\n")
                        
                        print("Models update [\(Date().formatted(date: .omitted, time: .standard))]:\n\(modelInfo)")
                    }
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

