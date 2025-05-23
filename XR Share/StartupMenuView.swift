import SwiftUI

struct StartupMenuView: View {
    @Binding var hasSelectedMode: Bool
    @EnvironmentObject var arViewModel: ARViewModel
    
    @State private var isJoiningSession = false
    @State private var isEnteringSessionName = false
    @State private var sessionNameInput = ""
    @State private var showingAnimation = false
    
    var body: some View {
        ZStack {
            // Modern gradient background
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color(.secondarySystemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Animated background elements
            GeometryReader { geometry in
                ForEach(0..<3) { i in
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [DesignSystem.Colors.primary.opacity(0.1), DesignSystem.Colors.accent.opacity(0.1)],
                                center: .center
                            )
                        )
                        .frame(width: 200, height: 200)
                        .offset(
                            x: geometry.size.width * CGFloat(i) * 0.3 - 100,
                            y: geometry.size.height * CGFloat(i) * 0.2 - 50
                        )
                        .scaleEffect(showingAnimation ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 3.0 + Double(i) * 0.5)
                            .repeatForever(autoreverses: true),
                            value: showingAnimation
                        )
                }
            }
            .opacity(0.3)
            
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xl) {
                    // Logo section with modern styling
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        Image("logo_white")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 120)
                            .shadow(
                                color: DesignSystem.Effects.cardShadow,
                                radius: 20,
                                x: 0,
                                y: 10
                            )
                            .scaleEffect(showingAnimation ? 1.0 : 0.8)
                            .animation(
                                .spring(response: 0.8, dampingFraction: 0.6)
                                .delay(0.2),
                                value: showingAnimation
                            )
                        
                        VStack(spacing: DesignSystem.Spacing.sm) {
                            Text("XRShare")
                                .font(DesignSystem.Typography.largeTitle)
                                .foregroundColor(DesignSystem.Colors.label)
                                .opacity(showingAnimation ? 1.0 : 0.0)
                                .animation(
                                    .easeInOut(duration: 0.8)
                                    .delay(0.5),
                                    value: showingAnimation
                                )
                            
                            Text("Collaborative AR Experiences")
                                .font(DesignSystem.Typography.subheadline)
                                .foregroundColor(DesignSystem.Colors.secondaryLabel)
                                .opacity(showingAnimation ? 1.0 : 0.0)
                                .animation(
                                    .easeInOut(duration: 0.8)
                                    .delay(0.7),
                                    value: showingAnimation
                                )
                        }
                    }
                    .padding(.top, DesignSystem.Spacing.xxxl)
                    
                    // Main content card
                    VStack(spacing: DesignSystem.Spacing.lg) {
                        if isJoiningSession {
                            SessionDiscoveryView(
                                sessions: arViewModel.availableSessions,
                                onSelectSession: { session in
                                    withAnimation(.spring()) {
                                        arViewModel.invitePeer(session)
                                        isJoiningSession = false
                                        hasSelectedMode = true
                                    }
                                },
                                onCancel: {
                                    withAnimation(.spring()) {
                                        isJoiningSession = false
                                    }
                                }
                            )
                        } else {
                            MainMenuView(
                                onHostSession: {
                                    withAnimation(.spring()) {
                                        isEnteringSessionName = true
                                    }
                                },
                                onJoinSession: {
                                    withAnimation(.spring()) {
                                        arViewModel.userRole = .viewer
                                        arViewModel.startMultipeerServices()
                                        isJoiningSession = true
                                    }
                                },
                                onLocalSession: {
                                    withAnimation(.spring()) {
                                        arViewModel.userRole = .localSession
                                        arViewModel.sessionName = "LocalSession"
                                        arViewModel.sessionID = UUID().uuidString
                                        hasSelectedMode = true
                                    }
                                }
                            )
                        }
                    }
                    .spatialCard(material: .thick)
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .opacity(showingAnimation ? 1.0 : 0.0)
                    .offset(y: showingAnimation ? 0 : 50)
                    .animation(
                        .spring(response: 0.8, dampingFraction: 0.8)
                        .delay(0.9),
                        value: showingAnimation
                    )
                    
                    Spacer(minLength: DesignSystem.Spacing.xl)
                }
            }
            
            // Spatial session name input overlay
            if isEnteringSessionName {
                SpatialSessionNameInput(
                    isPresented: $isEnteringSessionName,
                    sessionName: $sessionNameInput
                ) {
                    arViewModel.sessionName = sessionNameInput
                    arViewModel.userRole = .host
                    arViewModel.sessionID = UUID().uuidString
                    arViewModel.startMultipeerServices()
                    hasSelectedMode = true
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.9)),
                    removal: .opacity.combined(with: .scale(scale: 1.1))
                ))
            }
        }
        .onAppear {
            OrientationManager.shared.lock(to: .portrait)
            withAnimation {
                showingAnimation = true
            }
        }
        .onDisappear {
            OrientationManager.shared.unlock()
            showingAnimation = false
        }
    }
}

// MARK: - Main Menu Component

struct MainMenuView: View {
    let onHostSession: () -> Void
    let onJoinSession: () -> Void
    let onLocalSession: () -> Void
    
    private let menuItems = [
        MenuItemData(title: "Host Session", subtitle: "Start a new collaborative AR session", icon: "person.3", color: DesignSystem.Colors.constructive),
        MenuItemData(title: "Join Session", subtitle: "Connect to an existing session", icon: "link", color: DesignSystem.Colors.neutral),
        MenuItemData(title: "Local Session", subtitle: "Practice offline without networking", icon: "iphone", color: DesignSystem.Colors.iconSecondary)
    ]
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Text("Choose Session Type")
                .font(DesignSystem.Typography.title2)
                .foregroundColor(DesignSystem.Colors.label)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: DesignSystem.Spacing.md) {
                ForEach(Array(menuItems.enumerated()), id: \.offset) { index, item in
                    MenuItemCard(
                        item: item,
                        action: {
                            switch index {
                            case 0: onHostSession()
                            case 1: onJoinSession()
                            case 2: onLocalSession()
                            default: break
                            }
                        }
                    )
                }
            }
        }
    }
}

struct MenuItemData {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
}

struct MenuItemCard: View {
    let item: MenuItemData
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Icon container - spatial glass design
                RoundedRectangle(cornerRadius: DesignSystem.Sizing.smallCornerRadius)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignSystem.Sizing.smallCornerRadius)
                            .fill(DesignSystem.Colors.glassBackground)
                    }
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: item.icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.iconPrimary)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignSystem.Sizing.smallCornerRadius)
                            .stroke(DesignSystem.Colors.glassBorder, lineWidth: 1)
                    }
                
                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text(item.subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.tertiaryLabel)
            }
            .padding(DesignSystem.Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.Sizing.cornerRadius)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignSystem.Sizing.cornerRadius)
                            .stroke(DesignSystem.Colors.glassBorder, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Session Discovery Component

struct SessionDiscoveryView: View {
    let sessions: [Session]
    let onSelectSession: (Session) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Available Sessions")
                        .font(DesignSystem.Typography.title2)
                        .foregroundColor(DesignSystem.Colors.label)
                    
                    Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s") found")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryLabel)
                }
                
                Spacer()
                
                // Animated searching indicator
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DesignSystem.Colors.iconSecondary)
                        .symbolEffect(.pulse, options: .repeating)
                    
                    Text("Searching...")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryLabel)
                }
            }
            
            if sessions.isEmpty {
                // Empty state
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 40))
                        .foregroundColor(DesignSystem.Colors.tertiaryLabel)
                    
                    Text("No Sessions Found")
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.secondaryLabel)
                    
                    Text("Make sure other devices are hosting sessions nearby")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.tertiaryLabel)
                        .multilineTextAlignment(.center)
                }
                .padding(DesignSystem.Spacing.xl)
            } else {
                // Sessions list
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(sessions, id: \.sessionID) { session in
                        SessionCard(session: session) {
                            onSelectSession(session)
                        }
                    }
                }
            }
            
            // Cancel button
            Button("Cancel") {
                onCancel()
            }
            .buttonStyle(SpatialSecondaryButtonStyle())
        }
    }
}

struct SessionCard: View {
    let session: Session
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Session icon
                Circle()
                    .fill(DesignSystem.Colors.glassBackground)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "person.2")
                            .foregroundColor(DesignSystem.Colors.iconSecondary)
                    }
                
                // Session info
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.sessionName)
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.label)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Text("Hosted by \(session.peerID.displayName)")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(DesignSystem.Colors.iconSecondary)
                    .font(.title2)
            }
            .padding(DesignSystem.Spacing.md)
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.Sizing.cornerRadius)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignSystem.Sizing.cornerRadius)
                            .stroke(DesignSystem.Colors.glassBorder, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Modern Session Name Input

struct SpatialSessionNameInput: View {
    @Binding var isPresented: Bool
    @Binding var sessionName: String
    let onContinue: () -> Void
    
    @FocusState private var focused: Bool
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring()) {
                        isPresented = false
                    }
                }
            
            // Content card
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Header
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Text("Session Name")
                        .font(DesignSystem.Typography.title2)
                        .foregroundColor(DesignSystem.Colors.label)
                    
                    Text("Choose a name for your collaborative session")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryLabel)
                        .multilineTextAlignment(.center)
                }
                
                // Text field
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    TextField("Enter session name", text: $sessionName)
                        .font(DesignSystem.Typography.body)
                        .padding(DesignSystem.Spacing.md)
                        .background {
                            RoundedRectangle(cornerRadius: DesignSystem.Sizing.cornerRadius)
                                .fill(.regularMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: DesignSystem.Sizing.cornerRadius)
                                        .stroke(focused ? DesignSystem.Colors.primary : DesignSystem.Colors.controlBorder, lineWidth: 2)
                                }
                        }
                        .focused($focused)
                        .submitLabel(.done)
                        .onSubmit {
                            if !sessionName.isEmpty {
                                isPresented = false
                                onContinue()
                            }
                        }
                    
                    if sessionName.isEmpty {
                        Text("Session name is required")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundColor(DesignSystem.Colors.error)
                    }
                }
                
                // Action buttons
                HStack(spacing: DesignSystem.Spacing.md) {
                    Button("Cancel") {
                        withAnimation(.spring()) {
                            isPresented = false
                        }
                    }
                    .buttonStyle(SpatialSecondaryButtonStyle())
                    
                    Button("Start Session") {
                        withAnimation(.spring()) {
                            isPresented = false
                            onContinue()
                        }
                    }
                    .buttonStyle(SpatialPrimaryButtonStyle())
                    .disabled(sessionName.isEmpty)
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .background {
                RoundedRectangle(cornerRadius: DesignSystem.Sizing.cornerRadius)
                    .fill(.regularMaterial)
                    .shadow(
                        color: DesignSystem.Effects.cardShadow,
                        radius: 20,
                        x: 0,
                        y: 10
                    )
            }
            .frame(maxWidth: 350)
            .padding(DesignSystem.Spacing.lg)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focused = true
            }
        }
    }
}

// MARK: - Preview

struct StartupMenuView_Previews: PreviewProvider {
    static var previews: some View {
        StartupMenuView(hasSelectedMode: .constant(false))
            .environmentObject(ARViewModel())
            .preferredColorScheme(.light)
        
        StartupMenuView(hasSelectedMode: .constant(false))
            .environmentObject(ARViewModel())
            .preferredColorScheme(.dark)
    }
}
