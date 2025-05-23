import RealityKit
import SwiftUI
import Combine

/// Generates and manages 2D preview images for 3D models
@MainActor
class ModelPreviewGenerator: ObservableObject {
    static let shared = ModelPreviewGenerator()
    
    @Published private(set) var previewCache: [String: UIImage] = [:]
    @Published private var loadingStates: [String: Bool] = [:]
    
    private var cancellables = Set<AnyCancellable>()
    private let previewSize = CGSize(width: 200, height: 200)
    
    private init() {}
    
    /// Get a preview image for a model type
    func getPreview(for modelType: ModelType) -> UIImage? {
        let cacheKey = modelType.rawValue
        
        // Check if we have a cached preview
        if let cachedImage = previewCache[cacheKey] {
            return cachedImage
        }
        
        // Check if we're already loading this preview
        if loadingStates[cacheKey] == true {
            return nil
        }
        
        // Start loading the preview
        loadPreview(for: modelType)
        return nil
    }
    
    /// Load or generate a preview for a model
    private func loadPreview(for modelType: ModelType) {
        let cacheKey = modelType.rawValue
        loadingStates[cacheKey] = true
        
        Task { @MainActor in
            do {
                // First try to load a pre-made thumbnail image
                if let thumbnailImage = await loadThumbnailImage(for: modelType) {
                    previewCache[cacheKey] = thumbnailImage
                    loadingStates[cacheKey] = false
                    return
                }
                
                // If no thumbnail exists, generate one from the 3D model
                if let generatedImage = await generatePreviewFromModel(for: modelType) {
                    previewCache[cacheKey] = generatedImage
                    loadingStates[cacheKey] = false
                    return
                }
                
                // Fallback to a default image
                previewCache[cacheKey] = createDefaultPreviewImage(for: modelType)
                loadingStates[cacheKey] = false
                
            } catch {
                print("Failed to load preview for \(modelType.rawValue): \(error)")
                previewCache[cacheKey] = createDefaultPreviewImage(for: modelType)
                loadingStates[cacheKey] = false
            }
        }
    }
    
    /// Try to load a pre-made thumbnail image from the bundle
    private func loadThumbnailImage(for modelType: ModelType) async -> UIImage? {
        // Look for thumbnail images in the bundle
        let possibleNames = [
            "\(modelType.rawValue)_thumbnail",
            "\(modelType.rawValue)_preview",
            "\(modelType.rawValue)"
        ]
        
        for imageName in possibleNames {
            if let image = UIImage(named: imageName) {
                return image
            }
            
            // Also check in the models directory
            if let url = Bundle.main.url(forResource: imageName, withExtension: "jpg", subdirectory: "models"),
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                return image
            }
            
            if let url = Bundle.main.url(forResource: imageName, withExtension: "png", subdirectory: "models"),
               let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {
                return image
            }
        }
        
        return nil
    }
    
    /// Generate a preview image from the 3D model using RealityKit
    private func generatePreviewFromModel(for modelType: ModelType) async -> UIImage? {
        do {
            // Load the model entity
            let filename = "\(modelType.rawValue).usdz"
            let modelEntity: ModelEntity
            
            if let modelURL = Bundle.main.url(forResource: modelType.rawValue, withExtension: "usdz", subdirectory: "models") {
                modelEntity = try await ModelEntity(contentsOf: modelURL)
            } else {
                modelEntity = try await ModelEntity(named: filename, in: Bundle.main)
            }
            
            // Create a preview scene
            return await generatePreviewImage(from: modelEntity)
            
        } catch {
            print("Failed to generate preview from model \(modelType.rawValue): \(error)")
            return nil
        }
    }
    
    /// Generate a preview image from a ModelEntity using snapshot
    private func generatePreviewImage(from modelEntity: ModelEntity) async -> UIImage? {
        #if os(iOS)
        // Create a temporary ARView for rendering
        let arView = ARView(frame: CGRect(origin: .zero, size: previewSize))
        
        // Create an anchor to hold the model
        let anchor = AnchorEntity(.world(transform: matrix_identity_float4x4))
        arView.scene.addAnchor(anchor)
        
        // Add the model to the anchor
        anchor.addChild(modelEntity)
        
        // Position and scale the model for optimal preview
        let bounds = modelEntity.visualBounds(relativeTo: nil)
        let maxDimension = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
        let scale: Float = 0.5 / maxDimension // Scale to fit nicely in preview
        modelEntity.scale = SIMD3<Float>(repeating: scale)
        
        // Center the model
        modelEntity.position = -bounds.center * scale
        
        // Position the model at a good viewing distance and angle
        // Since we can't move the camera, we move the anchor instead
        anchor.position = SIMD3<Float>(0, 0, -1) // Move model away from camera
        anchor.orientation = simd_quatf(angle: 0.3, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: 0.3, axis: SIMD3<Float>(1, 0, 0))
        
        // Wait a frame for rendering to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Take a snapshot
        return await arView.snapshotAsync()
        #else
        // visionOS fallback - return nil to use default icon
        print("Preview generation not supported on visionOS, using default icon")
        return nil
        #endif
    }
    
    /// Create a default preview image with the model icon
    private func createDefaultPreviewImage(for modelType: ModelType) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: previewSize)
        
        return renderer.image { context in
            // Background gradient
            let colors = [UIColor.systemGray6.cgColor, UIColor.systemGray5.cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: previewSize.height), options: [])
            
            // Draw the model icon
            let iconSize: CGFloat = 80
            let iconRect = CGRect(
                x: (previewSize.width - iconSize) / 2,
                y: (previewSize.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
            
            let iconName = modelIconName(for: modelType)
            let config = UIImage.SymbolConfiguration(pointSize: iconSize * 0.6, weight: .medium)
            let icon = UIImage(systemName: iconName, withConfiguration: config)
            
            context.cgContext.setFillColor(UIColor.label.cgColor)
            icon?.draw(in: iconRect)
            
            // Add model name
            let nameRect = CGRect(x: 10, y: previewSize.height - 30, width: previewSize.width - 20, height: 20)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraphStyle
            ]
            
            modelType.rawValue.draw(in: nameRect, withAttributes: attributes)
        }
    }
    
    /// Get the appropriate SF Symbol icon name for a model type
    private func modelIconName(for modelType: ModelType) -> String {
        switch modelType.rawValue.lowercased() {
        case let name where name.contains("heart"):
            return "heart.fill"
        case let name where name.contains("brain"):
            return "brain.head.profile"
        case let name where name.contains("pancake"):
            return "circle.fill"
        case let name where name.contains("artery"), let name where name.contains("arteries"):
            return "drop.fill"
        default:
            return "cube.fill"
        }
    }
    
    /// Clear all cached previews (useful for memory management)
    func clearCache() {
        previewCache.removeAll()
        loadingStates.removeAll()
    }
    
    /// Check if a preview is currently loading
    func isLoading(for modelType: ModelType) -> Bool {
        return loadingStates[modelType.rawValue] == true
    }
}

// MARK: - SwiftUI Integration

/// A view that displays a model preview with loading state
struct ModelPreviewView: View {
    let modelType: ModelType
    let size: CGSize
    
    init(modelType: ModelType, size: CGSize = CGSize(width: 80, height: 80)) {
        self.modelType = modelType
        self.size = size
    }
    
    var body: some View {
        // Use the unified preview system for consistency across platforms
        UnifiedModelPreview(modelType: modelType, size: size)
    }
}

#if os(iOS)
extension ARView {
    /// Take a snapshot of the current ARView content
    @MainActor
    func snapshotAsync() async -> UIImage? {
        return await withCheckedContinuation { continuation in
            self.snapshot(saveToHDR: false) { image in
                continuation.resume(returning: image)
            }
        }
    }
}
#endif
