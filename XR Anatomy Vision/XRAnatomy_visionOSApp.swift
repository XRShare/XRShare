import SwiftUI
import ARKit

// MARK: - App state manager
class AppState: ObservableObject {
    @Published var imageTrackingProvider: ImageTrackingProvider? = nil
    @Published var isImageTracked: Bool = false
    @Published var alertItem: AlertItem? = nil
    
    // Auto-start image tracking mode
    @Published var autoStartImageTracking: Bool = true
    
    // This function might be redundant if ARViewModel gets ModelManager directly
    // func setupModelManager(modelManager: ModelManager, arViewModel: ARViewModel) {
    //     // Link model manager with view model
    //     arViewModel.modelManager = modelManager
    // }
    
    // Handle image tracking setup
    func startTracking(imageProvider: ImageTrackingProvider) {
        imageTrackingProvider = imageProvider
    }
    
    // Stop tracking
    func stopTracking() {
        imageTrackingProvider = nil
        isImageTracked = false
    }
}

@main
struct XRAnatomy_visionOSApp: App {
    @Environment(\.dismissWindow) var dismiss
    @StateObject private var appModel = AppModel()
    @StateObject private var arViewModel = ARViewModel()
    @StateObject private var modelManager = ModelManager()
    @StateObject private var appState = AppState()
    @State var session = ARKitSession()
    
    var body: some Scene {
        WindowGroup {
            ContentView(modelManager: modelManager)
                .environmentObject(appModel)
                .environmentObject(arViewModel)
                .environmentObject(appState)
                .withWindowOpener() // Add our window opener capability
                .onAppear {
                    // Assign ModelManager to ARViewModel immediately
                    arViewModel.modelManager = modelManager
                    
                    appModel.immersiveSpaceState = .closed
                    
                    // Initialize models and state (setupModelManager might be redundant now)
                    // appState.setupModelManager(modelManager: modelManager, arViewModel: arViewModel)
                    
                    // Check which environment we're running in
                    #if targetEnvironment(simulator)
                    print("Running in simulator - using World sync mode by default")
                    arViewModel.currentSyncMode = .world
                    #else
                    print("Running on device - using Image Target sync mode by default")
                    arViewModel.currentSyncMode = .imageTarget
                    #endif
                    
                    print("Starting with sync mode: \(arViewModel.currentSyncMode.rawValue)")
                }
        }
        .windowStyle(.plain)
        .windowResizability(.automatic)
        
        
        // Single unified debug/control panel
        WindowGroup(id: "controlPanel") {
            DebugControlsView(modelManager: modelManager, arViewModel: arViewModel)
                .environmentObject(appModel)
                .environmentObject(appState)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 400, height: 600)
        .windowResizability(.automatic)
        
        
        WindowGroup(id: "AddModelWindow"){
                
            AddModelView(modelManager: modelManager)
                .environmentObject(arViewModel)
                .environmentObject(appModel)
                .environmentObject(appState)
            
        }
        .windowStyle(.automatic)
        .defaultSize(width: 400, height: 600)
        .windowResizability(.automatic)
        
        
        WindowGroup(id: "MainMenuView"){
            MainMenu()
                .environmentObject(arViewModel)
                .environmentObject(appModel)
                .environmentObject(appState)
                .onAppear {
                    dismiss(id: "InSessionView")
                    dismiss(id: "AddModelWindow")
                }
        }
        
        
        WindowGroup(id: "InSessionView"){
            ModelSelectionScreen(modelManager: modelManager)
                .environmentObject(arViewModel)
                .environmentObject(appModel)
                .environmentObject(appState)
                .onAppear {
                    dismiss(id: "MainMenuView")
                }
            
        }
        
        WindowGroup{id: "MoreInfoView"){
            
            ModelInformationView(modelManager: modelManager)
                .environmentObject(arViewModel)
                .environmentObject(appModel)
                .environmentObject(appState)
        }
            
        }


        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            InSession(modelManager: modelManager, session: session)
                .environmentObject(appModel)
                .environmentObject(arViewModel)
                .environmentObject(appState)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("syncModeChanged"))) { _ in
                    Task {
                        print("Received sync mode change notification, reconfiguring AR session...")
                        await configureARSession()
                    }
                }
                .task {
                    print("ImmersiveSpace task running...")
                    await configureARSession() // Configure session on initial appear
                }
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
    
    // Function to configure ARKitSession based on current sync mode
    @MainActor
    func configureARSession() async {
        let currentMode = arViewModel.currentSyncMode
        print("Configuring ARKitSession for mode: \(currentMode.rawValue)...")
        
        // Always include world tracking
        var providers: [any DataProvider] = [
            WorldTrackingProvider()
        ]

        // Add plane detection only if not running on simulator
        #if !targetEnvironment(simulator)
        providers.append(PlaneDetectionProvider(alignments: [.horizontal, .vertical]))
        print("PlaneDetectionProvider added for device.")
        #else
        print("PlaneDetectionProvider skipped for simulator.")
        // Force world mode on simulator
        if currentMode == .imageTarget {
            print("Image tracking not supported in simulator, switching to world mode")
            arViewModel.currentSyncMode = .world
            // Call self recursively - now with world mode
            await configureARSession()
            return
        }
        #endif
        
        // Clear existing provider reference
        appState.stopTracking()
        
        if currentMode == .imageTarget {
            // Load reference images
            // Use the correct group name from your assets
            let referenceImages = ReferenceImage.loadReferenceImages(inGroupNamed: "SharedAnchors")
            if referenceImages.isEmpty {
                print("Error: Failed to load any reference images from group 'SharedAnchors'")
                
                appState.alertItem = AlertItem(title: "Error", message: "Could not load Image Target resources. Switching back to World Sync.")
                arViewModel.currentSyncMode = .world
                
                await configureARSession() // Reconfigure for world mode
                return
            }
            print("Loaded \(referenceImages.count) reference images for Image Target mode.")
            
            // Create and add ImageTrackingProvider
            let imageProvider = ImageTrackingProvider(referenceImages: referenceImages)
            providers.append(imageProvider)
            
            // Store provider reference through the app state
            appState.startTracking(imageProvider: imageProvider)
        }
        
        do {
            // Stop session before running with new providers (important for provider changes)
            session.stop() // Stop previous run
            try await session.run(providers)
            print("ARKitSession running with providers: \(providers.map { type(of: $0) })")
            // Start image monitoring if in the correct mode AFTER session starts
            await startImageMonitoring()
        } catch {
            print("Error running ARKitSession: \(error)")
            
            appState.alertItem = AlertItem(title: "AR Error", message: "Failed to start AR Session: \(error.localizedDescription)")
            
            if arViewModel.currentSyncMode == .imageTarget {
                arViewModel.currentSyncMode = .world
                
                // If we switched to world mode, try again
                await configureARSession() 
            }
        }
    }
    
    @MainActor
    func startImageMonitoring() async {
        // Use the app state to get tracking provider
        let currentMode = arViewModel.currentSyncMode
        let provider = appState.imageTrackingProvider
        
        guard currentMode == .imageTarget, let imageProvider = provider else {
            print("Not starting image monitoring (Mode: \(currentMode.rawValue), Provider: \(provider == nil ? "nil" : "exists"))")
            appState.isImageTracked = false // Ensure state is false if not monitoring
            return
        }
        
        print("Starting Image Anchor monitoring...")
        
        Task {
            // Using a throwable pattern to get the compiler to understand this can throw
            do {
                // This is needed to ensure the compiler sees this as potentially throwing
                try Task.checkCancellation()
                
                for await anchorUpdate in imageProvider.anchorUpdates {
                    // Check mode again in case it changed while awaiting
                    if arViewModel.currentSyncMode != .imageTarget {
                        print("Image Anchor Task: Exiting, mode changed during anchor update.")
                        break // Exit loop
                    }
                    
                    let imageAnchor = anchorUpdate.anchor
                    let event = anchorUpdate.event
                    
                    // Use any of the reference images
                    let imageName = imageAnchor.referenceImage.name ?? "Unknown"
                    
                    // Using the AppState and ARViewModel objects directly within the MainActor context
                    switch event {
                    case .added, .updated:
                        let imageName = imageAnchor.referenceImage.name ?? "Unknown"
                        if imageAnchor.isTracked {
                            // Image is currently tracked
                            if !arViewModel.isSyncedToImage {
                                // Perform the one-time sync alignment
                                let newWorldTransform = imageAnchor.originFromAnchorTransform
                                arViewModel.sharedAnchorEntity.setTransformMatrix(newWorldTransform, relativeTo: nil)
                                arViewModel.isSyncedToImage = true // Mark as synced
                                appState.isImageTracked = true // Mark as detected
                                print("✅ Image Target '\(imageName)' detected. Synced sharedAnchorEntity transform.")
                            } else {
                                // Already synced, just update detection status if it wasn't already tracked
                                if !appState.isImageTracked {
                                     appState.isImageTracked = true
                                     print("👀 Image Target '\(imageName)' re-detected (already synced).")
                                }
                            }
                        } else {
                            // Image is lost
                            if appState.isImageTracked {
                                print("⚠️ Image Target '\(imageName)' lost tracking.")
                                appState.isImageTracked = false
                                // DO NOT reset isSyncedToImage here - alignment persists
                            }
                        }
                    case .removed:
                        let imageName = imageAnchor.referenceImage.name ?? "Unknown"
                        if appState.isImageTracked {
                            print("❌ Image Target '\(imageName)' anchor removed.")
                            appState.isImageTracked = false
                            // DO NOT reset isSyncedToImage here
                        }
                    @unknown default:
                        print("Unhandled image anchor event: \(event)")
                    }
                } // End loop (anchorUpdates)
            } catch {
                // This can happen if the provider stops while we're iterating
                print("Error occurred during image anchor monitoring: \(error)")
            }
            
            // Ensure detection state is false if task finishes or exits loop
            // isSyncedToImage persists until explicitly reset
            if appState.isImageTracked {
                print("Image monitoring loop finished/exited, resetting detection state.")
                appState.isImageTracked = false
            }
        }
    }
}
