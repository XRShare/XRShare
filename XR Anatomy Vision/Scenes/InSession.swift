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
    @Environment(\.dismissWindow) private var dismissWindow
    
    @ObservedObject var modelManager: ModelManager
    @StateObject private var sessionConnectivity = SessionConnectivity()
    @StateObject private var entityModel = EntityModel()
    
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
    
    // State for Drag Gesture
    @State private var draggedEntity: Entity? = nil
    // Store initial positions for drag calculation
    @State private var initialDragEntityPosition: SIMD3<Float>? = nil // Keep for potential alternative logic
    @State private var gestureStartLocation3D: Point3D? = nil // Keep for potential alternative logic
    @State private var previousDragLocation3D: Point3D? = nil // For delta calculation


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
                // Ensure models are correctly parented based on sync mode
                for model in modelManager.placedModels {
                    guard let entity = model.modelEntity else { continue }

                    // Determine the INTENDED parent based on the current sync mode
                    let intendedParent: Entity?
                    let intendedParentName: String
                    switch arViewModel.currentSyncMode {
                    case .imageTarget, .objectTarget:
                        // Ensure shared anchor is in the scene before considering it the intended parent
                        if arViewModel.sharedAnchorEntity.scene == nil {
                            // Check if it's in the RealityView content but not yet assigned to the scene graph
                            if content.entities.contains(arViewModel.sharedAnchorEntity) {
                                // It exists in content, likely okay to parent to, scene assignment might be pending
                                intendedParent = arViewModel.sharedAnchorEntity
                            } else {
                                // Not in content, add it first
                                content.add(arViewModel.sharedAnchorEntity)
                                print("Added sharedAnchorEntity to content in update (was missing).")
                                intendedParent = arViewModel.sharedAnchorEntity
                            }
                        } else {
                            intendedParent = arViewModel.sharedAnchorEntity
                        }
                        intendedParentName = "sharedAnchorEntity (\(arViewModel.currentSyncMode.rawValue))"
                    case .world:
                        // Ensure model anchor is in the scene
                        if modelAnchor.scene == nil {
                             if content.entities.contains(modelAnchor) {
                                 intendedParent = modelAnchor
                             } else {
                                 content.add(modelAnchor)
                                 print("Added modelAnchor to content in update (was missing).")
                                 intendedParent = modelAnchor
                             }
                        } else {
                            intendedParent = modelAnchor
                        }
                        intendedParentName = "modelAnchor (World)"
                    }

                    // Get the current parent
                    let currentParent = entity.parent

                    // Reparent ONLY if the current parent is different from the intended parent
                    if currentParent !== intendedParent {
                        // Log the reparenting action
                        print("Reparenting \(entity.name): Current parent (\(currentParent?.name ?? "nil")) != Intended parent (\(intendedParentName)). SyncMode: \(arViewModel.currentSyncMode.rawValue)")

                        // Ensure the intended parent is valid before reparenting
                        if let validIntendedParent = intendedParent {
                            // Preserve world transform during reparenting to avoid visual jumps
                            entity.setParent(validIntendedParent, preservingWorldTransform: true)
                            print("Successfully reparented \(entity.name) to \(intendedParentName).")

                            // After reparenting, update the model's local state if needed (optional)
                            // model.position = entity.position(relativeTo: validIntendedParent)
                            // model.rotation = entity.orientation(relativeTo: validIntendedParent)
                            // model.scale = entity.scale(relativeTo: validIntendedParent)

                        } else {
                            print("Warning: Cannot reparent \(entity.name) because intended parent (\(intendedParentName)) is nil or not ready.")
                            // If intended parent is nil, maybe remove the entity? Or leave it detached?
                            // For now, just log the warning.
                        }
                    }
                    // Else: Entity already has the correct parent, no action needed.
                }

                // Update model selection highlights and broadcast transforms
                // This function now assumes entities are correctly parented by the logic above.
                modelManager.updatePlacedModels(
                    arViewModel: arViewModel
                )
            }
            // --- visionOS Gestures ---
                .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded ({ value in
                    
                    print("🎯 Tapped entity: \(value.entity.name)")
                    
                    let entity = value.entity
                    let name = entity.name
                    
                    
                    let previous = entityModel.currentEntity
                    entityModel.currentEntity = .named(name)
                    
                    if case .named(let oldName) = previous, oldName == name {
                        entityModel.currentEntity = .none
                    }
                    
                    
                    if modelManager.isInfoModeActive {
                        self.dismissWindow(id: appModel.detailViewID, value: name )
                        self.openWindow(id: appModel.detailViewID, value: name)
                    }

                        // print("Spatial Tap detected on entity: \(value.entity.name)")
                          // Call handleTap on the main actor
                          
                        //  Task{ @MainActor in
                        //   if modelManager.isInfoModeActive {
                               //   print("Tapped part: \(value.entity.name)")
                                 
                                  
                               //   modelManager.selectedPartInfo = modelManager.pancakeInfo(for: value.entity.name)
                               //   dismissWindow(id: "SelectedPartInfoWindow")
                               //   openWindow(id: "SelectedPartInfoWindow")
                         //     } else{
                           //       modelManager.handleTap(entity: value.entity)
                             // }
                              
                         // }
                      }
                  ))
            
            
            .simultaneousGesture(DragGesture()
                 .targetedToAnyEntity()
                 .onChanged { value in
                     // Ensure the entity is managed
                     guard modelManager.modelDict[value.entity] != nil else {
                         // print("Attempted drag on unmanaged entity: \(value.entity.name)")
                         return
                     }

                     // Store entity being dragged
                     if draggedEntity == nil {
                         draggedEntity = value.entity
                         print("Drag started on: \(value.entity.name)")
                     }
                     // Ensure we are continuing to drag the same entity
                     guard let currentDraggedEntity = draggedEntity, value.entity == currentDraggedEntity else {
                         return
                     }

                     let currentDragLocation = value.location3D

                     // On the first change event for this entity, just store the location
                     guard let previousLocation = previousDragLocation3D else {
                         previousDragLocation3D = currentDragLocation
                         print("Drag first update for \(currentDraggedEntity.name) at \(currentDragLocation)")
                         return
                     }

                     // Calculate the delta translation vector in world space
                     let delta = currentDragLocation - previousLocation
                     let deltaSIMD = SIMD3<Float>(Float(delta.x), Float(delta.y), Float(delta.z))

                     // Get the entity's current world position
                     let currentWorldPosition = currentDraggedEntity.position(relativeTo: nil)

                     // Calculate the new target world position
                     // Pass the raw world-space delta to the ModelManager
                     Task { @MainActor in
                         // Check if the entity still exists before handling drag change
                         if modelManager.modelDict[currentDraggedEntity] != nil {
                             modelManager.handleDragChange(entity: currentDraggedEntity, translation: deltaSIMD, arViewModel: arViewModel)
                         }
                     }

                     // Update the previous location for the next frame
                     previousDragLocation3D = currentDragLocation

                     lastGestureEvent = "Dragging \(currentDraggedEntity.name)"
                 }
                 .onEnded { value in
                     // Use the stored draggedEntity for ending the gesture
                     guard let entityToEnd = draggedEntity else {
                         // print("Drag ended: No entity was being tracked.") // Reduce log noise
                         // Reset state just in case
                         previousDragLocation3D = nil
                         return
                     }

                     // Final position update happened in onChanged.
                     // Call handleDragEnd for consistency and final broadcast.
                     Task { @MainActor in
                         // Check if the entity still exists before finalizing
                         if modelManager.modelDict[entityToEnd] != nil {
                             modelManager.handleDragEnd(entity: entityToEnd, arViewModel: arViewModel)
                             print("Drag ended successfully for \(entityToEnd.name)")
                         } else {
                             print("Drag ended: Entity \(entityToEnd.name) no longer managed.")
                         }
                     }
                     lastGestureEvent = "Drag ended for \(entityToEnd.name)"

                     // Reset drag state reliably
                     draggedEntity = nil
                     previousDragLocation3D = nil // Reset previous location
                     // Reset other potentially stale states if they were used
                     initialDragEntityPosition = nil
                     gestureStartLocation3D = nil
                 }
            )
             .simultaneousGesture(MagnifyGesture()
                 .targetedToAnyEntity()
                 .onChanged { value in
                     let scaleFactor = Float(value.magnification)
                     Task { @MainActor in
                         modelManager.handleScaleChange(entity: value.entity, scaleFactor: scaleFactor, arViewModel: arViewModel)
                     }
                     lastGestureEvent = "Scaling \(value.entity.name) by \(String(format: "%.2f", scaleFactor))"
                 }
                 .onEnded { value in
                      Task { @MainActor in
                          modelManager.handleScaleEnd(entity: value.entity, arViewModel: arViewModel)
                      }
                      lastGestureEvent = "Scale ended for \(value.entity.name)"
                 }
             )
             // Using RotateGesture3D for potentially more intuitive rotation
             .simultaneousGesture(RotateGesture3D()
                 .targetedToAnyEntity()
                 .onChanged { value in
                     let rotation = simd_quatf(value.rotation) // Convert Euler angles to quaternion
                     Task { @MainActor in
                         modelManager.handleRotationChange(entity: value.entity, rotation: rotation, arViewModel: arViewModel)
                     }
                     lastGestureEvent = "Rotating \(value.entity.name)"
                 }
                 .onEnded { value in
                     Task { @MainActor in
                         modelManager.handleRotationEnd(entity: value.entity, arViewModel: arViewModel)
                     }
                     lastGestureEvent = "Rotation ended for \(value.entity.name)"
                 }
             )
            
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

