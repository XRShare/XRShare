import SwiftUI

// MARK: - Enhanced Model Ornament

struct EnhancedModelOrnament: View {
    let model: Model
    let onInfo: () -> Void
    let onInteractionMode: () -> Void
    let onRemove: () -> Void
    let onSpeak: () -> Void
    let isInfoModeActive: Bool
    
    @State private var hoveredButton: OrnamentButton? = nil
    
    enum OrnamentButton {
        case info, interaction, remove, speak
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Model info button
            OrnamentButtonView(
                icon: "info.circle",
                label: "Details",
                isHovered: hoveredButton == .info
            ) {
                onInfo()
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    hoveredButton = hovering ? .info : nil
                }
            }
            
            // Interaction mode button
            OrnamentButtonView(
                icon: "hand.tap",
                label: "Select Parts",
                isActive: isInfoModeActive,
                isHovered: hoveredButton == .interaction
            ) {
                onInteractionMode()
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    hoveredButton = hovering ? .interaction : nil
                }
            }
            
            // Remove button
            OrnamentButtonView(
                icon: "trash",
                label: "Remove",
                tintColor: .red,
                isHovered: hoveredButton == .remove
            ) {
                onRemove()
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    hoveredButton = hovering ? .remove : nil
                }
            }
            
            // Speak button (future feature)
            OrnamentButtonView(
                icon: "speaker.wave.3",
                label: "Narrate",
                isDisabled: true,
                isHovered: hoveredButton == .speak
            ) {
                onSpeak()
            }
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    hoveredButton = hovering ? .speak : nil
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thickMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .hoverEffect(.lift)
    }
}

struct OrnamentButtonView: View {
    let icon: String
    let label: String
    var tintColor: Color = .primary
    var isActive: Bool = false
    var isDisabled: Bool = false
    var isHovered: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(
                        isDisabled ? Color.secondary :
                        isActive ? Color.blue :
                        tintColor == .red ? Color.red :
                        Color.primary
                    )
                    .scaleEffect(isHovered ? 1.1 : 1.0)
                
                Text(label)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(
                        isDisabled ? Color.secondary : Color.secondary
                    )
            }
            .frame(width: 60, height: 44)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.blue.opacity(0.2))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.blue.opacity(0.4), lineWidth: 1)
                        }
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.1))
                }
            }
        }
        .buttonStyle(.borderless)
        .disabled(isDisabled)
        .hoverEffect(.highlight)
    }
}