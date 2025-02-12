import SwiftUI
import RealityKit

struct ImmersiveSpaceView: View {
    @StateObject private var arViewModel = RealityViewModel()
    @State private var initialPosition: SIMD3<Float>? = nil
    @State private var initialScale: SIMD3<Float>? = nil
    
    var body: some View {
        RealityView { content in
            await setupContent(content: &content)
        }
        .gesture(translationGesture)
        .gesture(scaleGesture)
        .edgesIgnoringSafeArea(.all)
        .onAppear {
            print("ImmersiveSpaceView onAppear")
            arViewModel.onAppear()
        }
        .onDisappear {
            arViewModel.onDisappear()
        }
    }
    
    private func setupContent(content: inout RealityViewContent) async {
        do {
            // Example: place one default model
            let modelName = "heart2K"
            let modelEntity = try await arViewModel.loadModel(named: modelName)

            let bounds = modelEntity.visualBounds(relativeTo: nil)
            let collisionBox = ShapeResource.generateBox(
                width: bounds.extents.x,
                height: bounds.extents.y,
                depth: bounds.extents.z
            )
            modelEntity.components.set(CollisionComponent(shapes: [collisionBox]))
            modelEntity.components.set(InputTargetComponent())
            
            modelEntity.position = SIMD3<Float>(0, -bounds.min.y, -1.0)
            let anchor = AnchorEntity(world: modelEntity.position)
            anchor.addChild(modelEntity)

            content.add(anchor)
        } catch {
            print("Failed to load \(error)")
        }
    }
    
    var translationGesture: some Gesture {
        DragGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                let entity = value.entity
                if initialPosition == nil { initialPosition = entity.position }
                let movement = value.convert(value.translation3D, from: .global, to: .scene)
                entity.position = (initialPosition ?? .zero) + SIMD3<Float>(movement.x, 0, movement.z)
            }
            .onEnded { _ in
                initialPosition = nil
            }
    }

    var scaleGesture: some Gesture {
        MagnifyGesture()
            .targetedToAnyEntity()
            .onChanged { value in
                let entity = value.entity
                if initialScale == nil { initialScale = entity.scale }
                entity.scale = (initialScale ?? .one) * Float(value.gestureValue.magnification)
            }
            .onEnded { _ in
                initialScale = nil
            }
    }
}
