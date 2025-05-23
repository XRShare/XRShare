import SwiftUI

// MARK: - Design System
/// Shared design system for consistent styling across iOS and visionOS
struct DesignSystem {
    
    // MARK: - Colors
    struct Colors {
        // Primary brand colors
        static let primary = Color.blue
        static let primaryDark = Color.blue.opacity(0.8)
        static let accent = Color.cyan
        
        // Semantic colors that adapt to light/dark mode
        static let background = Color(.systemBackground)
        static let secondaryBackground = Color(.secondarySystemBackground)
        static let tertiaryBackground = Color(.tertiarySystemBackground)
        
        static let label = Color(.label)
        static let secondaryLabel = Color(.secondaryLabel)
        static let tertiaryLabel = Color(.tertiaryLabel)
        
        // Status colors
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        
        // Glass and overlay colors
        static let glassTint = Color.white.opacity(0.1)
        static let overlayBackground = Color.black.opacity(0.3)
        
        // Platform-specific colors
        #if os(iOS)
        static let controlBackground = Color(.systemFill)
        static let controlBorder = Color(.separator)
        #else
        static let controlBackground = Color.clear
        static let controlBorder = Color.clear
        #endif
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
        static let cardShadowRadius: CGFloat = 10
        static let cardShadowOffset: CGSize = CGSize(width: 0, height: 4)
        
        static let buttonShadow = Color.black.opacity(0.2)
        static let buttonShadowRadius: CGFloat = 8
        static let buttonShadowOffset: CGSize = CGSize(width: 0, height: 2)
    }
}

// MARK: - Custom View Modifiers

struct CardStyle: ViewModifier {
    let padding: CGFloat
    
    init(padding: CGFloat = DesignSystem.Sizing.cardPadding) {
        self.padding = padding
    }
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                #if os(iOS)
                RoundedRectangle(cornerRadius: DesignSystem.Sizing.cornerRadius)
                    .fill(.regularMaterial)
                    .shadow(
                        color: DesignSystem.Effects.cardShadow,
                        radius: DesignSystem.Effects.cardShadowRadius,
                        x: DesignSystem.Effects.cardShadowOffset.width,
                        y: DesignSystem.Effects.cardShadowOffset.height
                    )
                #else
                RoundedRectangle(cornerRadius: DesignSystem.Sizing.cornerRadius)
                    .fill(.regularMaterial)
                    .glassBackgroundEffect()
                #endif
            }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
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
                RoundedRectangle(cornerRadius: DesignSystem.Sizing.cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: isDestructive 
                                ? [DesignSystem.Colors.error, DesignSystem.Colors.error.opacity(0.8)]
                                : [DesignSystem.Colors.primary, DesignSystem.Colors.primaryDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(
                        color: DesignSystem.Effects.buttonShadow,
                        radius: configuration.isPressed ? 4 : DesignSystem.Effects.buttonShadowRadius,
                        x: 0,
                        y: configuration.isPressed ? 1 : DesignSystem.Effects.buttonShadowOffset.height
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.headline)
            .foregroundColor(DesignSystem.Colors.primary)
            .frame(height: DesignSystem.Sizing.buttonHeight)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.Sizing.cornerRadius)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignSystem.Sizing.cornerRadius)
                            .stroke(DesignSystem.Colors.primary, lineWidth: 2)
                    }
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct FloatingButtonStyle: ButtonStyle {
    let backgroundColor: Color
    
    init(backgroundColor: Color = DesignSystem.Colors.primary) {
        self.backgroundColor = backgroundColor
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: DesignSystem.Sizing.iconSize, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 56, height: 56)
            .background {
                Circle()
                    .fill(backgroundColor)
                    .shadow(
                        color: DesignSystem.Effects.buttonShadow,
                        radius: configuration.isPressed ? 4 : 12,
                        x: 0,
                        y: configuration.isPressed ? 2 : 6
                    )
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
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

extension View {
    func cardStyle(padding: CGFloat = DesignSystem.Sizing.cardPadding) -> some View {
        modifier(CardStyle(padding: padding))
    }
    
    func statusIndicator(_ status: StatusIndicatorStyle.ConnectionStatus) -> some View {
        modifier(StatusIndicatorStyle(status: status))
    }
}