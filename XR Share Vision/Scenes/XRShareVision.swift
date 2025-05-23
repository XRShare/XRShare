import SwiftUI
import ARKit

// MARK: - visionOS App entry point

@main
struct XRShareVision: App {
    @Environment(\.dismissWindow) var dismiss
    @StateObject private var appModel = AppModel()
    @StateObject private var arViewModel = ARViewModel()
    @StateObject private var modelManager = ModelManager()
    @StateObject private var appState = AppState()
    @State var session = ARKitSession()
    
    var body: some Scene {
        WindowGroup(id: "MainMenu") {
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
                    
                    // Image target sync is the only supported mode
                    print("Using Image Target sync mode")
                    
                    print("Starting with sync mode: \(arViewModel.currentSyncMode.rawValue)")
                }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 600, height: 450)
        .windowResizability(.automatic)
        
        
        // Single unified debug/control panel
        WindowGroup(id: "controlPanel") {
            DebugControlsView(modelManager: modelManager, arViewModel: arViewModel)
                .environmentObject(appModel)
                .environmentObject(appState)
                .onDisappear {
                    // Ensure the state reflects the window being closed
                    appModel.controlPanelVisible = false
                    print("DebugControlsView disappeared, setting controlPanelVisible to false.")
                }
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
        .defaultSize(width: 400, height: 700)
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
                    dismiss(id: "MainMenu")
                }
            
        }
        .windowStyle(.automatic)
        .defaultSize(width: 700, height: 850)
        
        
        WindowGroup(id: "ModelInfoWindow"){
                        
                ModelInformationView(modelManager: modelManager)
                        .environmentObject(arViewModel)
                        .environmentObject(appModel)
                        .environmentObject(appState)
                    
                }
                .windowStyle(.automatic)
                .defaultSize(width: 400, height: 400)
                .windowResizability(.automatic)
        
        WindowGroup(id: appModel.detailViewID, for: String.self){ value in
            
            SelectedPartInfoScreen(modelManager: modelManager, title: value.wrappedValue!)
                .environmentObject(arViewModel)
                .environmentObject(appModel)
                .environmentObject(appState)
        }
            .windowStyle(.automatic)
            .defaultSize(width: 325, height: 325)
            .windowResizability(.automatic)
        
        
        
        WindowGroup(id: "ModelMenuBar"){
            ModelMenuBar(modelManager: modelManager)
                .environmentObject(arViewModel)
                .environmentObject(appModel)
                .environmentObject(appState)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 600, height: 100)
        .windowResizability(.automatic)
        


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
        // Check if this is a local session
        if arViewModel.userRole == .localSession {
            print("Configuring ARKitSession for Local mode (no sync)...")
            
            // For local sessions, only use world tracking
            var providers: [any DataProvider] = [
                WorldTrackingProvider()
            ]
            
            // Add plane detection only if not running on simulator
            #if !targetEnvironment(simulator)
            providers.append(PlaneDetectionProvider(alignments: [.horizontal, .vertical]))
            print("PlaneDetectionProvider added for device.")
            #else
            print("PlaneDetectionProvider skipped for simulator.")
            #endif
            
            do {
                // Stop session before running with new providers
                session.stop()
                try await session.run(providers)
                print("ARKitSession running in Local mode with providers: \(providers.map { type(of: $0) })")
            } catch {
                print("Error running ARKitSession in Local mode: \(error)")
                appState.alertItem = AlertItem(title: "AR Error", message: "Failed to start AR Session: \(error.localizedDescription)")
            }
            return
        }
        
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
        // Image tracking not supported in simulator
        if currentMode == .imageTarget {
            print("Error: Image tracking not supported in simulator")
            appState.alertItem = AlertItem(title: "Error", message: "Image tracking is not supported in simulator.")
            return
        }
        #endif

        // Clear existing provider references
        appState.stopTracking()
        arViewModel.isSyncedToImage = false // Reset sync flags

        if currentMode == .imageTarget {
            // --- Image Target Mode ---
            let referenceImages = ReferenceImage.loadReferenceImages(inGroupNamed: "SharedAnchors")
            if referenceImages.isEmpty {
                print("Error: Failed to load any reference images from group 'SharedAnchors'")
                appState.alertItem = AlertItem(title: "Error", message: "Could not load Image Target resources.")
                return
            }
            print("Loaded \(referenceImages.count) reference images for Image Target mode.")
            let imageProvider = ImageTrackingProvider(referenceImages: referenceImages)
            providers.append(imageProvider)
            appState.startImageTracking(provider: imageProvider) // Use updated AppState method

        }

        do {
            // Stop session before running with new providers
            session.stop()
            try await session.run(providers)
            print("ARKitSession running with providers: \(providers.map { type(of: $0) })")
            // Start monitoring for image target mode AFTER session starts
            if currentMode == .imageTarget {
                await startImageMonitoring()
            }
        } catch {
            print("Error running ARKitSession: \(error)")
            appState.alertItem = AlertItem(title: "AR Error", message: "Failed to start AR Session: \(error.localizedDescription)")

            // Image tracking failed
            if arViewModel.currentSyncMode == .imageTarget {
                print("Failed to start Image Target tracking")
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
            arViewModel.isImageTracked = false // Ensure state is false if not monitoring
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
                    // Capture the image target's name for logging
                    let imageName = imageAnchor.referenceImage.name ?? "Unknown"
                    
                    // Use any of the reference images
                    
                    // Using the AppState and ARViewModel objects directly within the MainActor context
                    switch event {
                    case .added, .updated:
                        if imageAnchor.isTracked {
                            // Image is currently tracked
                            if !arViewModel.isSyncedToImage {
                                // Perform the one-time sync alignment
                                let newWorldTransform = imageAnchor.originFromAnchorTransform
                                arViewModel.sharedAnchorEntity.setTransformMatrix(newWorldTransform, relativeTo: nil)
                                arViewModel.isSyncedToImage = true // Mark as synced
                        arViewModel.isImageTracked = true // Mark as detected
                                print("Image Target '\(imageName)' detected. Synced sharedAnchorEntity transform.")
                            } else {
                                // Already synced, just update detection status if it wasn't already tracked
                            if !arViewModel.isImageTracked {
                                     arViewModel.isImageTracked = true
                                     print("Image Target '\(imageName)' re-detected (already synced).")
                            }
                            }
                        } else {
                            // Image is lost
                            if arViewModel.isImageTracked {
                                print("Image Target '\(imageName)' lost tracking.")
                                arViewModel.isImageTracked = false
                                // DO NOT reset isSyncedToImage here - alignment persists
                            }
                        }
                    case .removed:
                        if arViewModel.isImageTracked {
                            print("Image Target '\(imageName)' anchor removed.")
                            arViewModel.isImageTracked = false
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
            if arViewModel.isImageTracked {
                print("Image monitoring loop finished/exited, resetting detection state.")
                arViewModel.isImageTracked = false
            }
        }
    }

}
