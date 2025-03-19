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
    @Environment(\.openWindow) private var openWindow
    
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
    @State private var timerCounter = 0

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
            
            // 3D debug panel that's visible in the scene
            RealityView { content in
                // Add a debug panel entity that floats in 3D space
                let panelMesh = MeshResource.generatePlane(width: 0.25, height: 0.12)
                let panelMaterial = SimpleMaterial(color: .blue, isMetallic: false)
                let debugPanel = ModelEntity(mesh: panelMesh, materials: [panelMaterial])
                
                // Position panel in front of user but offset to the side
                debugPanel.position = SIMD3<Float>(-0.25, 0.05, -0.5)
                
                // Make panel face the user
                debugPanel.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
                
                // Add to scene
                content.add(debugPanel)
                
                // Make panel interactive for movement
                debugPanel.collision = CollisionComponent(shapes: [.generateBox(size: debugPanel.visualBounds(relativeTo: nil).extents)])
                debugPanel.components.set(InputTargetComponent())
                debugPanel.components.set(HoverEffectComponent())
                
                // Store reference to the panel
                debugPanel.name = "DebugPanel"
            } update: { _ in 
                // Panel updates handled by SwiftUI overlay
            }
            
            // SwiftUI overlay for debug info that stays in your field of view
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Text("XR Anatomy")
                        .font(.headline.bold())
                        .foregroundColor(.white)
                    
                    Text(modelStats)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {
                        showDebugInfo.toggle()
                    }) {
                        Label(showDebugInfo ? "Hide Controls" : "Show Controls", 
                              systemImage: showDebugInfo ? "eye.slash" : "eye")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.8))
                .cornerRadius(20)
                .shadow(radius: 5)
                
                if showDebugInfo {
                    HStack(spacing: 12) {
                        // Control panel button
                        Button(action: {
                            Task { @MainActor in
                                async let _ = openWindow(id: "controlPanel")
                            }
                        }) {
                            VStack {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.title2)
                                Text("Controls")
                                    .font(.caption)
                            }
                            .frame(width: 70, height: 60)
                        }
                        .buttonStyle(.borderedProminent)
                        
                        // Reset position button
                        Button(action: {
                            if let firstModel = modelManager.placedModels.first,
                               let entity = firstModel.modelEntity {
                                entity.position = SIMD3<Float>(0, 0, -0.5)
                                firstModel.position = entity.position
                                
                                // Force update for multiplayer
                                if let arViewModel = firstModel.arViewModel {
                                    arViewModel.sendTransform(for: entity)
                                }
                            }
                        }) {
                            VStack {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.title2)
                                Text("Reset")
                                    .font(.caption)
                            }
                            .frame(width: 70, height: 60)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        
                        // Add model button
                        Button(action: {
                            if let heartType = modelManager.modelTypes.first(where: { $0.rawValue == "Heart" }) {
                                modelManager.loadModel(for: heartType, arViewModel: arViewModel)
                            } else if let firstModel = modelManager.modelTypes.first {
                                modelManager.loadModel(for: firstModel, arViewModel: arViewModel)
                            }
                        }) {
                            VStack {
                                Image(systemName: "plus.circle")
                                    .font(.title2)
                                Text("Add")
                                    .font(.caption)
                            }
                            .frame(width: 70, height: 60)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    .shadow(radius: 5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 50)
        }
        .onAppear {
            print("InSession has appeared. ModelManager has \(modelManager.placedModels.count) models loaded.")
            
            // Log all loaded model types for debugging
            print("Available model types: \(modelManager.modelTypes.map { $0.rawValue })")
            
            // Start multipeer services when the immersive space appears
            arViewModel.startMultipeerServices(modelManager: modelManager)
            
            // Open the control panel window programmatically
            // Using async let to properly handle the async operation
            Task {
                async let _ = openWindow(id: "controlPanel")
                print("Opened control panel window")
            }
            
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
