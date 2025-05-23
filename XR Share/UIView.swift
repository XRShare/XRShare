import SwiftUI
import RealityKit
import ARKit

struct XRAnatomyView: View {
    // Use EnvironmentObject to receive the instances created in the App struct
    @EnvironmentObject var arViewModel: ARViewModel
    @EnvironmentObject var modelManager: ModelManager // Receive ModelManager
    
    @State private var showModelMenu = false
    @State private var showResetConfirmation = false
    @State private var showSettingsOptions = false
    
    // Loading/Splash state
    @State private var isFirstLaunchLoading = false // Tracks if initial model load is happening
    @State private var loadingProgress: Float = 0.0 // Directly use arViewModel's progress
    @State private var showSplashScreen = !AppLoadTracker.hasRestarted // Show splash only on first cold start
    @State private var hasSelectedMode = false // Tracks if user picked Host/Join/Open
    
    // We no longer automatically start multi-peer, so we remove `hasStartedMultipeer`
    // var hasStartedMultipeer = false  // Removed or unused

    var body: some View {
        ZStack {
            if showSplashScreen {
                // Splash/loading screen for first launch.
                LoadingView(loadingProgress: $loadingProgress, showProgress: false)
            } else if isFirstLaunchLoading {
                LoadingView(loadingProgress: $loadingProgress)
            } else if !hasSelectedMode {
                // Show startup menu (Host / Join / Open).
                StartupMenuView(hasSelectedMode: $hasSelectedMode)
                    .environmentObject(arViewModel)
            } else {
                // Main AR container view.
                ZStack(alignment: .top) {
                    ARViewContainer()
                        .edgesIgnoringSafeArea(.all)
                        .environmentObject(arViewModel)
                    
                    // Top status bar
                    VStack {
                        ModernConnectionStatusView()
                            .environmentObject(arViewModel)
                            .padding(.top, DesignSystem.Spacing.sm)
                        Spacer()
                    }
                    
                    // Bottom control bar
                    VStack {
                        Spacer()
                        ModernControlBar(
                            onBack: handleBackButtonTap,
                            onModelSelect: { showModelMenu = true },
                            onReset: { showResetConfirmation = true },
                            onSettings: { showSettingsOptions = true },
                            onTogglePermission: {
                                arViewModel.isHostPermissionGranted.toggle()
                            },
                            showModelSelect: arViewModel.userRole != .viewer || arViewModel.isHostPermissionGranted,
                            showReset: arViewModel.userRole != .viewer || arViewModel.isHostPermissionGranted,
                            showPermissionToggle: arViewModel.userRole == .host,
                            isPermissionGranted: arViewModel.isHostPermissionGranted
                        )
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.bottom, DesignSystem.Spacing.lg)
                    }
                    
                    // Model selection sheet
                    if showModelMenu {
                        ModernModelSelectionView(
                            modelTypes: modelManager.modelTypes,
                            selectedModelType: modelManager.selectedModelID,
                            onSelectModel: { modelType in
                                withAnimation(.spring()) {
                                    showModelMenu = false
                                    modelManager.selectedModelID = modelType
                                    
                                    if let model = arViewModel.models.first(where: { $0.modelType == modelType }) {
                                        arViewModel.selectedModel = model
                                    }
                                    
                                    arViewModel.alertItem = AlertItem(
                                        title: "Model Selected",
                                        message: "Tap on a surface to place the \(modelType.rawValue)."
                                    )
                                }
                            },
                            onCancel: {
                                withAnimation(.spring()) {
                                    showModelMenu = false
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                    }
                    
                    // Modern settings panel
                    if showSettingsOptions {
                        ModernSettingsPanel(
                            isVisible: $showSettingsOptions,
                            arViewModel: arViewModel
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                    }
                }
                // Modern alert overlays
                if let alertItem = arViewModel.alertItem {
                    ModernAlert(
                        title: alertItem.title,
                        message: alertItem.message,
                        primaryAction: ModernAlert.Action(title: "OK") {
                            arViewModel.alertItem = nil
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)),
                        removal: .opacity.combined(with: .scale(scale: 1.1))
                    ))
                }
                
                if showResetConfirmation {
                    ModernAlert(
                        title: "Delete All Models",
                        message: "This will remove all models you've placed in the scene. This action cannot be undone.",
                        primaryAction: ModernAlert.Action(title: "Delete", isDestructive: true) {
                            showResetConfirmation = false
                            modelManager.reset()
                        },
                        secondaryAction: ModernAlert.Action(title: "Cancel") {
                            showResetConfirmation = false
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.9)),
                        removal: .opacity.combined(with: .scale(scale: 1.1))
                    ))
                }
            }
        }
        .onAppear {
            Task {
                await handleInitialLaunch()
            }
        }
        .onReceive(arViewModel.$loadingProgress) { progress in
            // Update local state
            loadingProgress = progress
            // If we just finished loading all models
            if progress >= 1.0, isFirstLaunchLoading {
                // We used to do "arViewModel.enableMultipeerServicesIfDeferred()" here,
                // but now we only start multipeer after user picks Host / Join in StartupMenuView.
                isFirstLaunchLoading = false
                Utilities.updateStoredModificationDate()
            }
        }
        .onReceive(arViewModel.$selectedSession) { session in
            // If your code auto-joins session -> show AR
            if session != nil { hasSelectedMode = true }
        }
    }
    
    /// The initial app launch logic
    private func handleInitialLaunch() async {
        if Utilities.isFirstLaunchForNewBuild() {
            // Show splash, load models
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isFirstLaunchLoading = true
                // We just load models, no multipeer yet
                Task {
                    await self.arViewModel.loadModels()
                }
                showSplashScreen = false
            }
        } else {
            // Not first launch -> skip splash, just load models
            showSplashScreen = false
            await arViewModel.loadModels()
        }
    }
    
    /// Called when user hits the back button in the AR view
    private func handleBackButtonTap() {
        // Stop the session so we can pick host/join again
        // Call methods directly on the arViewModel instance
        // First reset the AR session (which
        // also clears models), then tear down multipeer.
        arViewModel.resetARSession()
        arViewModel.stopMultipeerServices()
        hasSelectedMode = false // Return to main menu
    }
}

// MARK: - Modern AR Interface Components

struct ModernConnectionStatusView: View {
    @EnvironmentObject var arViewModel: ARViewModel
    
    private var connectionStatus: StatusIndicatorStyle.ConnectionStatus {
        if arViewModel.userRole == .localSession {
            return .disconnected
        } else if arViewModel.connectedPeers.isEmpty {
            return .searching
        } else {
            return .connected
        }
    }
    
    private var statusText: String {
        switch arViewModel.userRole {
        case .localSession:
            return "Local Session"
        case .host:
            if arViewModel.connectedPeers.isEmpty {
                return "Waiting for peers..."
            } else {
                return "Hosting • \(arViewModel.connectedPeers.count) connected"
            }
        case .viewer:
            if arViewModel.connectedPeers.isEmpty {
                return "Searching for sessions..."
            } else {
                return "Connected to session"
            }
        }
    }
    
    var body: some View {
        HStack {
            Spacer()
            Text(statusText)
                .statusIndicator(connectionStatus)
            Spacer()
        }
    }
}

struct ModernControlBar: View {
    let onBack: () -> Void
    let onModelSelect: () -> Void
    let onReset: () -> Void
    let onSettings: () -> Void
    let onTogglePermission: () -> Void
    
    let showModelSelect: Bool
    let showReset: Bool
    let showPermissionToggle: Bool
    let isPermissionGranted: Bool
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Back button
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: DesignSystem.Sizing.iconSize, weight: .semibold))
            }
            .buttonStyle(FloatingButtonStyle(backgroundColor: DesignSystem.Colors.error))
            
            Spacer()
            
            // Control buttons group
            HStack(spacing: DesignSystem.Spacing.sm) {
                if showModelSelect {
                    Button(action: onModelSelect) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: DesignSystem.Sizing.iconSize, weight: .semibold))
                    }
                    .buttonStyle(FloatingButtonStyle())
                }
                
                if showReset {
                    Button(action: onReset) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: DesignSystem.Sizing.iconSize, weight: .semibold))
                    }
                    .buttonStyle(FloatingButtonStyle(backgroundColor: DesignSystem.Colors.warning))
                }
                
                if showPermissionToggle {
                    Button(action: onTogglePermission) {
                        Image(systemName: isPermissionGranted ? "lock.open.fill" : "lock.fill")
                            .font(.system(size: DesignSystem.Sizing.iconSize, weight: .semibold))
                    }
                    .buttonStyle(FloatingButtonStyle(
                        backgroundColor: isPermissionGranted ? DesignSystem.Colors.success : DesignSystem.Colors.warning
                    ))
                }
                
                Button(action: onSettings) {
                    Image(systemName: "gear")
                        .font(.system(size: DesignSystem.Sizing.iconSize, weight: .semibold))
                }
                .buttonStyle(FloatingButtonStyle(backgroundColor: DesignSystem.Colors.secondaryBackground))
            }
        }
    }
}

struct ModernModelSelectionView: View {
    let modelTypes: [ModelType]
    let selectedModelType: ModelType?
    let onSelectModel: (ModelType) -> Void
    let onCancel: () -> Void
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }
            
            VStack {
                Spacer()
                
                // Content card
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // Header
                    HStack {
                        Text("Select Model")
                            .font(DesignSystem.Typography.title2)
                            .foregroundColor(DesignSystem.Colors.label)
                        
                        Spacer()
                        
                        Button("Cancel") {
                            onCancel()
                        }
                        .font(DesignSystem.Typography.callout)
                        .foregroundColor(DesignSystem.Colors.primary)
                    }
                    
                    // Model grid
                    LazyVGrid(columns: columns, spacing: DesignSystem.Spacing.md) {
                        ForEach(modelTypes, id: \.rawValue) { modelType in
                            ModelSelectionCard(
                                modelType: modelType,
                                isSelected: selectedModelType == modelType
                            ) {
                                onSelectModel(modelType)
                            }
                        }
                    }
                }
                .cardStyle()
                .frame(maxHeight: UIScreen.main.bounds.height * 0.6)
                .padding(DesignSystem.Spacing.lg)
            }
        }
    }
}

struct ModelSelectionCard: View {
    let modelType: ModelType
    let isSelected: Bool
    let action: () -> Void
    
    private var modelIcon: String {
        // Map model types to appropriate SF Symbols
        switch modelType.rawValue.lowercased() {
        case let name where name.contains("heart"):
            return "heart.fill"
        case let name where name.contains("brain"):
            return "brain.head.profile"
        case let name where name.contains("pancake"):
            return "circle.stack.fill"
        default:
            return "cube.fill"
        }
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: DesignSystem.Spacing.sm) {
                // Icon
                RoundedRectangle(cornerRadius: DesignSystem.Sizing.cornerRadius)
                    .fill(isSelected ? DesignSystem.Colors.primary.opacity(0.2) : DesignSystem.Colors.tertiaryBackground)
                    .frame(height: 80)
                    .overlay {
                        Image(systemName: modelIcon)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundColor(isSelected ? DesignSystem.Colors.primary : DesignSystem.Colors.secondaryLabel)
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: DesignSystem.Sizing.cornerRadius)
                                .stroke(DesignSystem.Colors.primary, lineWidth: 2)
                        }
                    }
                
                // Label
                Text(modelType.rawValue.capitalized)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.label)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .buttonStyle(.plain)
    }
}

struct ModernSettingsPanel: View {
    @Binding var isVisible: Bool
    @ObservedObject var arViewModel: ARViewModel
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring()) {
                        isVisible = false
                    }
                }
            
            VStack {
                Spacer()
                
                // Settings content
                VStack(spacing: DesignSystem.Spacing.lg) {
                    // Header
                    HStack {
                        Text("Debug Settings")
                            .font(DesignSystem.Typography.title2)
                            .foregroundColor(DesignSystem.Colors.label)
                        
                        Spacer()
                        
                        Button {
                            withAnimation(.spring()) {
                                isVisible = false
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(DesignSystem.Colors.tertiaryLabel)
                        }
                    }
                    
                    ScrollView {
                        VStack(spacing: DesignSystem.Spacing.md) {
                            // AR Debug Section
                            SettingsSection(title: "AR Debug Options") {
                                #if os(iOS)
                                SettingsToggle(
                                    title: "Plane Visualization",
                                    subtitle: "Show detected planes",
                                    isOn: $arViewModel.isPlaneVisualizationEnabled
                                ) { newValue in
                                    if newValue {
                                        arViewModel.arView?.debugOptions.insert(.showPhysics)
                                    } else {
                                        arViewModel.arView?.debugOptions.remove(.showPhysics)
                                    }
                                }
                                
                                SettingsToggle(
                                    title: "Feature Points",
                                    subtitle: "Show tracking feature points",
                                    isOn: $arViewModel.areFeaturePointsEnabled
                                ) { newValue in
                                    if newValue {
                                        arViewModel.arView?.debugOptions.insert(.showFeaturePoints)
                                    } else {
                                        arViewModel.arView?.debugOptions.remove(.showFeaturePoints)
                                    }
                                }
                                
                                SettingsToggle(
                                    title: "World Origin",
                                    subtitle: "Show coordinate system origin",
                                    isOn: $arViewModel.isWorldOriginEnabled
                                ) { newValue in
                                    if newValue {
                                        arViewModel.arView?.debugOptions.insert(.showWorldOrigin)
                                    } else {
                                        arViewModel.arView?.debugOptions.remove(.showWorldOrigin)
                                    }
                                }
                                
                                if ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
                                    SettingsToggle(
                                        title: "Person Occlusion",
                                        subtitle: "Hide objects behind people",
                                        isOn: $arViewModel.isSceneUnderstandingEnabled
                                    ) { newValue in
                                        Task { @MainActor in
                                            arViewModel.reconfigureARSession()
                                        }
                                        if newValue {
                                            arViewModel.arView?.environment.sceneUnderstanding.options.insert(.occlusion)
                                        } else {
                                            arViewModel.arView?.environment.sceneUnderstanding.options.remove(.occlusion)
                                        }
                                    }
                                }
                                #else
                                Text("Debug options not available on this platform")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.secondaryLabel)
                                #endif
                            }
                            
                            // Sync Section
                            SettingsSection(title: "Image Synchronization") {
                                ImageSyncStatus(arViewModel: arViewModel)
                                
                                Button("Re-Sync Image") {
                                    arViewModel.triggerSync()
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    }
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.5)
                }
                .cardStyle()
                .padding(DesignSystem.Spacing.lg)
            }
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text(title)
                .font(DesignSystem.Typography.headline)
                .foregroundColor(DesignSystem.Colors.label)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                content
            }
        }
    }
}

struct SettingsToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let onChange: (Bool) -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.label)
                
                Text(subtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryLabel)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.primary))
                .onChange(of: isOn, perform: onChange)
        }
        .padding(DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.tertiaryBackground)
        .cornerRadius(DesignSystem.Sizing.smallCornerRadius)
    }
}

struct ImageSyncStatus: View {
    @ObservedObject var arViewModel: ARViewModel
    
    private var statusColor: Color {
        if arViewModel.isSyncedToImage {
            return arViewModel.isImageTracked ? DesignSystem.Colors.success : DesignSystem.Colors.primary
        } else {
            return arViewModel.isImageTracked ? DesignSystem.Colors.warning : DesignSystem.Colors.error
        }
    }
    
    private var statusText: String {
        if arViewModel.isSyncedToImage {
            return arViewModel.isImageTracked ? "Image Detected (Synced)" : "Synced via Image (Not Detected)"
        } else {
            return arViewModel.isImageTracked ? "Image Detected (Syncing...)" : "Awaiting Image Sync..."
        }
    }
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .overlay {
                    if !arViewModel.isSyncedToImage && arViewModel.isImageTracked {
                        Circle()
                            .stroke(statusColor, lineWidth: 2)
                            .scaleEffect(1.5)
                            .opacity(0.7)
                            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: arViewModel.isImageTracked)
                    }
                }
            
            Text(statusText)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.label)
            
            Spacer()
        }
        .padding(DesignSystem.Spacing.sm)
        .background(statusColor.opacity(0.1))
        .cornerRadius(DesignSystem.Sizing.smallCornerRadius)
    }
}

struct ModernAlert: View {
    struct Action {
        let title: String
        let isDestructive: Bool
        let action: () -> Void
        
        init(title: String, isDestructive: Bool = false, action: @escaping () -> Void) {
            self.title = title
            self.isDestructive = isDestructive
            self.action = action
        }
    }
    
    let title: String
    let message: String
    let primaryAction: Action
    let secondaryAction: Action?
    
    init(
        title: String,
        message: String,
        primaryAction: Action,
        secondaryAction: Action? = nil
    ) {
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }
    
    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    if secondaryAction != nil {
                        secondaryAction?.action()
                    } else {
                        primaryAction.action()
                    }
                }
            
            // Alert content
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Icon based on alert type
                VStack(spacing: DesignSystem.Spacing.md) {
                    if primaryAction.isDestructive {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.warning)
                    } else {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 40, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.primary)
                    }
                    
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        Text(title)
                            .font(DesignSystem.Typography.title3)
                            .foregroundColor(DesignSystem.Colors.label)
                            .multilineTextAlignment(.center)
                        
                        Text(message)
                            .font(DesignSystem.Typography.callout)
                            .foregroundColor(DesignSystem.Colors.secondaryLabel)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                // Action buttons
                if let secondaryAction = secondaryAction {
                    // Two button layout
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Button(secondaryAction.title) {
                            withAnimation(.spring()) {
                                secondaryAction.action()
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        
                        Button(primaryAction.title) {
                            withAnimation(.spring()) {
                                primaryAction.action()
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle(isDestructive: primaryAction.isDestructive))
                    }
                } else {
                    // Single button layout
                    Button(primaryAction.title) {
                        withAnimation(.spring()) {
                            primaryAction.action()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle(isDestructive: primaryAction.isDestructive))
                }
            }
            .padding(DesignSystem.Spacing.xl)
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
            .frame(maxWidth: 320)
            .padding(DesignSystem.Spacing.lg)
        }
    }
}

// MARK: - Preview

struct XRAnatomyView_Previews: PreviewProvider {
    static var previews: some View {
        // Create dummy instances for preview
        let arViewModel = ARViewModel()
        let modelManager = ModelManager()
        arViewModel.modelManager = modelManager // Link them
        
        // Add some dummy model types for the preview
        modelManager.modelTypes = [ModelType(rawValue: "Heart"), ModelType(rawValue: "Brain")]
        arViewModel.models = modelManager.modelTypes.map { Model(modelType: $0, arViewModel: arViewModel) }
        
        return XRAnatomyView()
            .environmentObject(arViewModel)
            .environmentObject(modelManager)
    }
}