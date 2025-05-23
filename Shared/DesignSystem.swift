import SwiftUI

// MARK: - Design System
/// Shared design system for consistent styling across iOS and visionOS
struct DesignSystem {
    
    // MARK: - Colors (visionOS-Aligned 2025)
    struct Colors {
        // Spatial computing inspired - subtle, glass-like colors
        static let primary = Color.white
        static let primarySubtle = Color.white.opacity(0.8)
        static let accent = Color.white.opacity(0.6)
        
        // Semantic colors that adapt to light/dark mode
        static let background = Color(.systemBackground)
        static let secondaryBackground = Color(.secondarySystemBackground)
        static let tertiaryBackground = Color(.tertiarySystemBackground)
        
        static let label = Color(.label)
        static let secondaryLabel = Color(.secondaryLabel)
        static let tertiaryLabel = Color(.tertiaryLabel)
        
        // Subtle status colors - more muted for spatial design
        static let success = Color.green.opacity(0.8)
        static let warning = Color.orange.opacity(0.8)
        static let error = Color.red.opacity(0.8)
        
        // Glass materials - core to visionOS design
        static let glassBackground = Color.white.opacity(0.1)
        static let glassBorder = Color.white.opacity(0.2)
        static let glassHighlight = Color.white.opacity(0.3)
        
        // Spatial overlay colors
        static let spatialOverlay = Color.black.opacity(0.2)
        static let spatialBlur = Color.clear
        
        // Control colors - glass-first approach
        static let controlBackground = Color.white.opacity(0.15)
        static let controlBorder = Color.white.opacity(0.25)
        static let controlActive = Color.white.opacity(0.3)
        
        // Icon tints - subtle and refined
        static let iconPrimary = Color.white
        static let iconSecondary = Color.white.opacity(0.7)
        static let iconTertiary = Color.white.opacity(0.5)
        
        // Contextual colors for different actions
        static let destructive = Color.red.opacity(0.7)
        static let constructive = Color.green.opacity(0.7)
        static let neutral = Color.gray.opacity(0.7)
    }
    
    // MARK: - Typography
    struct Typography {
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title1 = Font.title.weight(.semibold)
        static let title2 = Font.title2.weight(.semibold)
        static let title3 = Font.title3.weight(.medium)
        static let headline = Font.headline.weight(.semibold)
        static let body = Font.body
        static let callout = Font.callout
        static let subheadline = Font.subheadline
        static let footnote = Font.footnote
        static let caption = Font.caption
        static let caption2 = Font.caption2
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64
        
        // Standard margins
        static let margin = md
        static let sectionSpacing = lg
        static let elementSpacing = sm
    }
    
    // MARK: - Sizing
    struct Sizing {
        static let buttonHeight: CGFloat = 50
        static let smallButtonHeight: CGFloat = 36
        static let controlHeight: CGFloat = 44
        static let cornerRadius: CGFloat = 12
        static let smallCornerRadius: CGFloat = 8
        static let iconSize: CGFloat = 24
        static let smallIconSize: CGFloat = 16
        
        // Platform-specific sizes
        #if os(iOS)
        static let cardPadding = Spacing.md
        static let maxContentWidth: CGFloat = .infinity
        #else
        static let cardPadding = Spacing.lg
        static let maxContentWidth: CGFloat = 400
        #endif
    }
    
    // MARK: - Shadows and Effects
    struct Effects {
        static let cardShadow = Color.black.opacity(0.1)
        // Spatial computing shadows - softer and more realistic
        static let spatialShadowRadius: CGFloat = 24
        static let spatialShadowOffset: CGSize = CGSize(width: 0, height: 12)
        
        static let buttonShadow = Color.black.opacity(0.1)
        static let buttonShadowRadius: CGFloat = 16
        static let buttonShadowOffset: CGSize = CGSize(width: 0, height: 8)
        
        // Glass effects
        static let glassShadow = Color.black.opacity(0.05)
        static let glassShadowRadius: CGFloat = 32
    }
}

// MARK: - Custom View Modifiers

struct SpatialCardStyle: ViewModifier {
    let padding: CGFloat
    let material: Material
    
    init(padding: CGFloat = DesignSystem.Sizing.cardPadding, material: Material = .regularMaterial) {
        self.padding = padding
        self.material = material
    }
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(material)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(DesignSystem.Colors.glassBackground)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                DesignSystem.Colors.glassBorder,
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: Color.black.opacity(0.08),
                        radius: 24,
                        x: 0,
                        y: 12
                    )
            }
    }
}

struct SpatialPrimaryButtonStyle: ButtonStyle {
    let isDestructive: Bool
    
    init(isDestructive: Bool = false) {
        self.isDestructive = isDestructive
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.headline)
            .foregroundColor(.white)
            .frame(height: DesignSystem.Sizing.buttonHeight)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                (isDestructive ? DesignSystem.Colors.destructive : DesignSystem.Colors.controlActive)
                                    .opacity(configuration.isPressed ? 0.4 : 0.3)
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                (isDestructive ? DesignSystem.Colors.destructive : DesignSystem.Colors.glassBorder)
                                    .opacity(0.5),
                                lineWidth: 1.5
                            )
                    }
                    .shadow(
                        color: Color.black.opacity(0.1),
                        radius: configuration.isPressed ? 8 : 16,
                        x: 0,
                        y: configuration.isPressed ? 2 : 8
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SpatialSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.headline)
            .foregroundColor(DesignSystem.Colors.label)
            .frame(height: DesignSystem.Sizing.buttonHeight)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                DesignSystem.Colors.glassBackground
                                    .opacity(configuration.isPressed ? 0.2 : 0.1)
                            )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                DesignSystem.Colors.glassBorder,
                                lineWidth: 1
                            )
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SpatialFloatingButtonStyle: ButtonStyle {
    let iconTint: Color
    let context: ButtonContext
    
    enum ButtonContext {
        case primary, secondary, destructive, constructive, neutral
        
        var backgroundOpacity: Double {
            switch self {
            case .primary: return 0.2
            case .secondary: return 0.15
            case .destructive: return 0.1
            case .constructive: return 0.1
            case .neutral: return 0.12
            }
        }
        
        var borderOpacity: Double {
            switch self {
            case .primary: return 0.4
            case .secondary: return 0.3
            case .destructive: return 0.3
            case .constructive: return 0.3
            case .neutral: return 0.25
            }
        }
        
        var accentColor: Color {
            switch self {
            case .primary, .secondary: return .white
            case .destructive: return .red
            case .constructive: return .green
            case .neutral: return .gray
            }
        }
    }
    
    init(iconTint: Color = DesignSystem.Colors.iconPrimary, context: ButtonContext = .primary) {
        self.iconTint = iconTint
        self.context = context
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: DesignSystem.Sizing.iconSize, weight: .medium))
            .foregroundColor(iconTint)
            .frame(width: 56, height: 56)
            .background {
                Circle()
                    .fill(.regularMaterial)
                    .overlay {
                        Circle()
                            .fill(context.accentColor.opacity(context.backgroundOpacity))
                    }
                    .overlay {
                        Circle()
                            .stroke(
                                context.accentColor.opacity(context.borderOpacity),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: Color.black.opacity(0.1),
                        radius: configuration.isPressed ? 6 : 16,
                        x: 0,
                        y: configuration.isPressed ? 2 : 8
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct StatusIndicatorStyle: ViewModifier {
    let status: ConnectionStatus
    
    enum ConnectionStatus {
        case connected, connecting, disconnected, searching
        
        var color: Color {
            switch self {
            case .connected: return DesignSystem.Colors.success
            case .connecting: return DesignSystem.Colors.warning
            case .disconnected: return DesignSystem.Colors.error
            case .searching: return DesignSystem.Colors.accent
            }
        }
        
        var systemImage: String {
            switch self {
            case .connected: return "checkmark.circle.fill"
            case .connecting: return "arrow.clockwise.circle"
            case .disconnected: return "xmark.circle.fill"
            case .searching: return "magnifyingglass.circle"
            }
        }
    }
    
    func body(content: Content) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: status.systemImage)
                .foregroundColor(status.color)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.pulse, options: .repeating, value: status == .connecting || status == .searching)
            
            content
                .font(DesignSystem.Typography.callout)
                .foregroundColor(DesignSystem.Colors.label)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background {
            Capsule()
                .fill(.regularMaterial)
                .overlay {
                    Capsule()
                        .stroke(status.color.opacity(0.3), lineWidth: 1)
                }
        }
    }
}

// MARK: - View Extensions

// MARK: - Material Extensions for Spatial Design
enum SpatialMaterial {
    case thin, regular, thick, ultraThin
    
    var material: Material {
        switch self {
        case .thin: return .thinMaterial
        case .regular: return .regularMaterial
        case .thick: return .thickMaterial
        case .ultraThin: return .ultraThinMaterial
        }
    }
}

extension View {
    func spatialCard(padding: CGFloat = DesignSystem.Sizing.cardPadding, material: SpatialMaterial = .regular) -> some View {
        modifier(SpatialCardStyle(padding: padding, material: material.material))
    }
    
    func statusIndicator(_ status: StatusIndicatorStyle.ConnectionStatus) -> some View {
        modifier(StatusIndicatorStyle(status: status))
    }
    
    // Spatial computing helper for glass effect
    func glassEffect(opacity: Double = 0.1) -> some View {
        self.background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    Rectangle()
                        .fill(Color.white.opacity(opacity))
                }
        }
    }
}