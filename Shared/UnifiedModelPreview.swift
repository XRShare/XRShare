import SwiftUI

/// Unified 2D model preview component that works consistently across iOS and visionOS
struct UnifiedModelPreview: View {
    let modelType: ModelType
    let size: CGSize
    let showBackground: Bool
    
    init(modelType: ModelType, size: CGSize = CGSize(width: 80, height: 80), showBackground: Bool = true) {
        self.modelType = modelType
        self.size = size
        self.showBackground = showBackground
    }
    
    /// Get the appropriate SF Symbol icon name for a model type
    private var modelIcon: String {
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
    
    /// Get color for the model category
    private var modelColor: Color {
        switch modelType.category {
        case .anatomy:
            return .red
        case .food:
            return .orange
        case .car:
            return .blue
        case .airplane:
            return .cyan
        case .bird:
            return .green
        case .none:
            return .gray
        }
    }
    
    var body: some View {
        ZStack {
            if showBackground {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.primary.opacity(0.2), lineWidth: 1)
                    }
            }
            
            VStack(spacing: 4) {
                Image(systemName: modelIcon)
                    .font(.system(size: size.width * 0.4, weight: .medium))
                    .foregroundColor(modelColor)
                
                Text(modelType.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Preview provider for Xcode previews
struct UnifiedModelPreview_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            HStack {
                UnifiedModelPreview(modelType: ModelType(rawValue: "Heart"))
                UnifiedModelPreview(modelType: ModelType(rawValue: "pancakes"))
                UnifiedModelPreview(modelType: ModelType(rawValue: "ArteriesHead"))
            }
            
            HStack {
                UnifiedModelPreview(
                    modelType: ModelType(rawValue: "Heart"), 
                    size: CGSize(width: 60, height: 60)
                )
                UnifiedModelPreview(
                    modelType: ModelType(rawValue: "pancakes"), 
                    size: CGSize(width: 120, height: 120)
                )
            }
        }
        .padding()
    }
}