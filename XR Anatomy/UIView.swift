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
                    
                    // Back button in bottom-left corner
                    VStack {
                        Spacer()
                        HStack {
                            Button(action: handleBackButtonTap) {
                                Image(systemName: "arrowshape.left")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .contentShape(Circle())
                                    .padding(10)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, -10)
                    .padding(.bottom, -20)
                    
                    // Connection status across top
                    VStack {
                        ConnectionStatusView()
                            .environmentObject(arViewModel)
                            .padding(.top, -5)
                            .frame(maxWidth: .infinity, alignment: .center)
                        Spacer()
                    }
                    
                    // Right side buttons
                    if arViewModel.userRole != .viewer || arViewModel.isHostPermissionGranted {
                        VStack(spacing: 10) {
                            // Model menu
                            Button(action: { showModelMenu.toggle() }) {
                                Image(systemName: "figure")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .contentShape(Circle())
                                    .padding(10)
                            }
                            .padding(.bottom, 30)
                            .actionSheet(isPresented: $showModelMenu) {
                                ActionSheet(
                                    title: Text("Select a Model"),
                                    buttons: modelManager.modelTypes.map { modelType in
                                        .default(Text(modelType.rawValue.capitalized)) {
                                            // Find the corresponding Model object if needed
                                            if let model = arViewModel.models.first(where: { $0.modelType == modelType }) {
                                                arViewModel.selectedModel = model
                                                print("Selected model for placement: \(modelType.rawValue)")
                                                // Show placement instructions
                                                arViewModel.alertItem = AlertItem(title: "Model Selected", message: "Tap on a surface to place the \(modelType.rawValue).")
                                            } else {
                                                print("Error: Could not find Model object for type \(modelType.rawValue)")
                                            }
                                        }
                                    } + [.cancel()]
                                )
                            }
                            
                            // Trash / reset
                            Button(action: { showResetConfirmation = true }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .contentShape(Circle())
                                    .padding(5)
                            }
                            .padding(.bottom, 190)
                            
                            // Host permission toggle
                            if arViewModel.userRole == .host {
                                Button(action: {
                                    arViewModel.isHostPermissionGranted.toggle() // Directly toggle the boolean property
                                }) {
                                    Image(systemName: arViewModel.isHostPermissionGranted ? "lock.open" : "lock")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .contentShape(Circle())
                                        .padding(10)
                                }
                            }
                            
                            // Debug settings
                            Button(action: { showSettingsOptions.toggle() }) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .contentShape(Circle())
                                    .padding(10)
                            }
                            .padding(.bottom, -10)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, -10)
                        .padding(.bottom, -10)
                    }
                    
                    // Bottom sheet for debug settings
                    if showSettingsOptions {
                        BottomSheet {
                            SettingsView(isVisible: $showSettingsOptions, arViewModel: arViewModel)
                        }
                        .transition(.move(edge: .bottom))
                        .animation(.easeInOut, value: showSettingsOptions)
                    }
                }
                .alert(item: $arViewModel.alertItem) { alertItem in
                    Alert(
                        title: Text(alertItem.title),
                        message: Text(alertItem.message),
                        dismissButton: .default(Text("OK"))
                    )
                }
                .alert(isPresented: $showResetConfirmation) {
                    Alert(
                        title: Text("Confirm Delete"),
                        message: Text("Are you sure you want to delete all models you've added?"),
                        primaryButton: .destructive(Text("Delete")) {
                            // Use ModelManager's reset method which handles entity cleanup
                            modelManager.reset()
                        },
                        secondaryButton: .cancel()
                    )
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
        arViewModel.stopMultipeerServices()
        arViewModel.resetARSession()
        hasSelectedMode = false // Return to main menu
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
