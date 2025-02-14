import SwiftUI
import RealityKit
import ARKit

struct UIView: View {
    @StateObject var arViewModel = ARViewModel()
    @State private var showModelMenu = false
    @State private var showResetConfirmation = false
    @State private var showSettingsOptions = false
    @State private var isFirstLaunchLoading = false
    @State private var loadingProgress: Float = 0.0
    @State private var hasStartedMultipeer = false
    @State private var showSplashScreen = !AppLoadTracker.hasRestarted
    @State private var hasSelectedMode = false

    var body: some View {
        ZStack {
            if showSplashScreen {
                // Show splash/loading screen on first launch.
                LoadingView(loadingProgress: $loadingProgress, showProgress: false)
            } else if isFirstLaunchLoading {
                LoadingView(loadingProgress: $loadingProgress)
            } else if !hasSelectedMode {
                // Show the startup menu
                StartupMenuView(hasSelectedMode: $hasSelectedMode)
                    .environmentObject(arViewModel)
            } else {
                // Main AR container view
                ZStack(alignment: .top) {
                    ARViewContainer(onSwipeFromLeftEdge: handleSwipeFromLeftEdge)
                        .edgesIgnoringSafeArea(.all)
                        .environmentObject(arViewModel)
                    
                    // Back button on left side
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
                    
                    // Connection status at top center
                    VStack {
                        ConnectionStatusView()
                            .environmentObject(arViewModel)
                            .padding(.top, -5)
                            .frame(maxWidth: .infinity, alignment: .center)
                        Spacer()
                    }
                    
                    // Right side buttons (model menu, clear, debug, etc.)
                    if arViewModel.userRole != .viewer || arViewModel.isHostPermissionGranted {
                        VStack(spacing: 10) {
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
                                    buttons: arViewModel.models.map { model in
                                        .default(Text(model.modelType.rawValue.capitalized)) {
                                            arViewModel.selectedModel = model
                                        }
                                    } + [.cancel()]
                                )
                            }
                            
                            Button(action: { showResetConfirmation = true }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .contentShape(Circle())
                                    .padding(5)
                            }
                            .padding(.bottom, 190)
                            
                            if arViewModel.userRole == .host {
                                Button(action: {
                                    arViewModel.toggleHostPermissions()
                                }) {
                                    Image(systemName: arViewModel.isHostPermissionGranted ? "lock.open" : "lock")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .contentShape(Circle())
                                        .padding(10)
                                }
                                .padding(.bottom, 0)
                            }
                            
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
                            arViewModel.clearAllModels()
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
        }
        .onAppear { handleInitialLaunch() }
        .onReceive(arViewModel.$loadingProgress) { progress in
            loadingProgress = progress
            if progress >= 1.0, isFirstLaunchLoading {
                arViewModel.enableMultipeerServicesIfDeferred()
                hasStartedMultipeer = true
                isFirstLaunchLoading = false
                Utilities.updateStoredModificationDate()
            }
        }
        .onReceive(arViewModel.$selectedSession) { session in
            if session != nil { hasSelectedMode = true }
        }
    }
    
    private func handleInitialLaunch() {
        if Utilities.isFirstLaunchForNewBuild() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isFirstLaunchLoading = true
                arViewModel.deferMultipeerServicesUntilModelsLoad()
                arViewModel.loadModels()
                showSplashScreen = false
            }
        } else {
            showSplashScreen = false
            arViewModel.startMultipeerServices()
            hasStartedMultipeer = true
            arViewModel.loadModels()
        }
    }
    
    private func handleBackButtonTap() {
        arViewModel.stopMultipeerServices()
        arViewModel.resetARSession()
        hasSelectedMode = false // Return to main menu
    }
    
    private func handleSwipeFromLeftEdge() {
        handleBackButtonTap()
    }
}

struct UIView_Previews: PreviewProvider {
    static var previews: some View {
        UIView()
    }
}
