import SwiftUI
import RealityKit

struct ImmersiveSpaceView: View {
    @StateObject private var arViewModel = RealityViewModel()
    @State private var initialPosition: SIMD3<Float>? = nil
    @State private var initialScale: SIMD3<Float>? = nil
    
    var body: some View {
        RealityView { content in
            print("Initializing RealityView content")
            
            // Initialize the environment
            await setupContent(content: &content)
        }
        .gesture(translationGesture)
        .gesture(scaleGesture)
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            print("ImmersiveSpaceView appeared")
            arViewModel.onAppear()
        }
        .onDisappear {
            arViewModel.onDisappear()
        }
    }
    
    /// Configures the RealityView content.
    private func setupContent(content: inout RealityViewContent) async {
        do {
            // Load and place the pancake model
            let modelName = "heart2K"
            print("Attempting to place model: \(modelName)")
            let modelEntity = try await arViewModel.loadModel(named: modelName)
            print("Model \(modelName) loaded successfully.")
            
            // Configure collision and input components for gestures
            let bounds = modelEntity.visualBounds(relativeTo: nil)
            let collisionBox = ShapeResource.generateBox(
                width: bounds.extents.x,
                height: bounds.extents.y,
                depth: bounds.extents.z
            )
            modelEntity.components.set(CollisionComponent(shapes: [collisionBox]))
            modelEntity.components.set(InputTargetComponent())
            print("Collision and input components set for \(modelName)")
            
            // Set model position and scale
            modelEntity.position = SIMD3<Float>(0, -bounds.min.y, -1.0)
//            modelEntity.scale = SIMD3<Float>(0.1, 0.1, 0.1)
            
            // Create an anchor for placement
            let anchor = AnchorEntity(world: modelEntity.position)
            anchor.addChild(modelEntity)
            print("Anchor created for model: \(modelName)")
            
            // Add the anchor to the content
            content.add(anchor)
            print("Anchor added to RealityView content.")
            
        } catch {
            print("Failed to load model: \(error.localizedDescription)")
        }
    }
    
    var translationGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                let entity = value.entity // Directly access the entity
                
                print("Translation gesture started for entity: \(entity.name)")
                
                // Set the initial position if not already set
                if initialPosition == nil {
                    initialPosition = entity.position
                }
                
                // Convert movement to scene coordinates
                let movement = value.convert(value.translation3D, from: .global, to: .scene)
                entity.position = (initialPosition ?? .zero) + SIMD3<Float>(movement.x, 0, movement.z)
                print("Entity moved to position: \(entity.position)")
            }
            .onEnded { _ in
                print("Translation gesture ended")
                initialPosition = nil
            }
    }
    
    var scaleGesture: some Gesture {
        MagnifyGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                let entity = value.entity // Directly access the entity
                
                print("Scaling gesture started for entity: \(entity.name)")
                
                // Set the initial scale if not already set
                if initialScale == nil {
                    initialScale = entity.scale
                }
                
                // Adjust the scale
                entity.scale = (initialScale ?? .one) * Float(value.gestureValue.magnification)
                print("Entity scaled to: \(entity.scale)")
            }
            .onEnded { _ in
                print("Scaling gesture ended")
                initialScale = nil
            }
    }
}
