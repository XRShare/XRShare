import SwiftUI
import RealityKit

/// A view that displays a 3D model preview in visionOS with rotation capability
struct Model3DPreviewView: View {
    let modelEntity: ModelEntity
    let allowsRotation: Bool
    
    @State private var rotation: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    @State private var scale: Float = 1.0
    
    init(modelEntity: ModelEntity, allowsRotation: Bool = true) {
        self.modelEntity = modelEntity
        self.allowsRotation = allowsRotation
    }
    
    var body: some View {
        #if os(visionOS)
        RealityView { content in
            setupModel(in: content)
        } update: { content in
            updateModel(in: content)
        }
        .gesture(
            allowsRotation ? 
            DragGesture()
                .onChanged { value in
                    let sensitivity: Float = 0.01
                    rotation.y += Float(value.translation.width) * sensitivity
                    rotation.x += Float(value.translation.height) * sensitivity
                }
            : nil
        )
        .gesture(
            MagnifyGesture()
                .onChanged { value in
                    scale = Float(value.magnification)
                }
        )
        #else
        // Fallback for non-visionOS platforms
        ModelPreviewView(
            modelType: ModelType(rawValue: modelEntity.name) ?? ModelType(rawValue: "unknown"),
            size: CGSize(width: 100, height: 100)
        )
        #endif
    }
    
    #if os(visionOS)
    private func setupModel(in content: RealityViewContent) {
        // Create a copy of the model entity for preview
        let previewEntity = modelEntity.clone(recursive: true)
        
        // Set up preview-specific properties
        previewEntity.name = "preview_\(modelEntity.name)"
        
        // Normalize size for preview
        let bounds = previewEntity.visualBounds(relativeTo: nil)
        let maxDimension = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
        if maxDimension > 0 {
            let targetSize: Float = 0.15 // 15cm for preview
            let scale = targetSize / maxDimension
            previewEntity.scale = SIMD3<Float>(repeating: scale)
        }
        
        // Center the model
        previewEntity.position = -bounds.center * previewEntity.scale.x
        
        // Add subtle rotation animation
        let rotationAnimation = FromToByAnimation<Transform>(
            to: Transform(rotation: simd_quatf(angle: .pi * 2, axis: SIMD3<Float>(0, 1, 0))),
            duration: 8.0,
            bindTarget: .transform
        )
        
        let animationResource = try? AnimationResource.generate(with: rotationAnimation)
        if let animationResource = animationResource {
            previewEntity.playAnimation(animationResource.repeat())
        }
        
        // Add to content
        content.add(previewEntity)
    }
    
    private func updateModel(in content: RealityViewContent) {
        // Update rotation if manually controlled
        if let previewEntity = content.entities.first(where: { $0.name.hasPrefix("preview_") }) {
            if allowsRotation {
                previewEntity.transform.rotation = simd_quatf(
                    angle: rotation.x,
                    axis: SIMD3<Float>(1, 0, 0)
                ) * simd_quatf(
                    angle: rotation.y,
                    axis: SIMD3<Float>(0, 1, 0)
                )
            }
            
            previewEntity.scale *= scale
            scale = 1.0 // Reset scale
        }
    }
    #endif
}

// MARK: - Enhanced Model Card for visionOS

/// A specialized model card component for visionOS with enhanced spatial features
struct VisionOSModelCard: View {
    let model: Model
    let onRemove: () -> Void
    let onExpand: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 3D Model Preview Section
            ZStack {
                // Glass background with depth
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.white.opacity(isHovered ? 0.15 : 0.08))
                    }
                
                // Model preview
                Group {
                    if let entity = model.modelEntity {
                        Model3DPreviewView(modelEntity: entity)
                            .scaleEffect(isHovered ? 1.05 : 1.0)
                    } else {
                        ModelPreviewView(
                            modelType: model.modelType,
                            size: CGSize(width: 120, height: 120)
                        )
                        .scaleEffect(isHovered ? 1.05 : 1.0)
                    }
                }
            }
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            
            // Information and Controls Section
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.modelType.rawValue)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        Text(model.modelType.category?.localizedName ?? "Unknown")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                }
                
                // Action buttons with ornament-style design
                HStack(spacing: 12) {
                    Spacer()
                    
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(width: 32, height: 32)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .hoverEffect(.highlight)
                    
                    Button(action: onExpand) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.borderless)
                    .hoverEffect(.highlight)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .frame(width: 320, height: 220)
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.1), radius: isHovered ? 16 : 8, x: 0, y: isHovered ? 8 : 4)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .hoverEffect(.lift)
    }
}