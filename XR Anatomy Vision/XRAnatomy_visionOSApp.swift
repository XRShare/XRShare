import SwiftUI
import ARKit

// MARK: - App state manager
class AppState: ObservableObject {
    // Tracking Providers
    @Published var imageTrackingProvider: ImageTrackingProvider? = nil
    @Published var objectTrackingProvider: ObjectTrackingProvider? = nil

    // Tracking Status
    @Published var isImageTracked: Bool = false
    @Published var isObjectTracked: Bool = false // New state for object tracking
    @Published var alertItem: AlertItem? = nil

    // Auto-start image tracking mode
    @Published var autoStartImageTracking: Bool = true
    
    // This function might be redundant if ARViewModel gets ModelManager directly
    // func setupModelManager(modelManager: ModelManager, arViewModel: ARViewModel) {
    //     // Link model manager with view model
    //     arViewModel.modelManager = modelManager
    // }
    
    // Handle image tracking setup
    func startImageTracking(provider: ImageTrackingProvider) {
        imageTrackingProvider = provider
        objectTrackingProvider = nil // Ensure only one provider is active
        isObjectTracked = false
    }

    // Handle object tracking setup
    func startObjectTracking(provider: ObjectTrackingProvider) {
        objectTrackingProvider = provider
        imageTrackingProvider = nil // Ensure only one provider is active
        isImageTracked = false
    }

    // Stop all tracking
    func stopTracking() {
        imageTrackingProvider = nil
        objectTrackingProvider = nil
        isImageTracked = false
        isObjectTracked = false
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
        
        
        WindowGroup(id: "ModelInfoWindow"){
                        
                ModelInformationView(modelManager: modelManager)
                        .environmentObject(arViewModel)
                        .environmentObject(appModel)
                        .environmentObject(appState)
                    
                }
                .windowStyle(.automatic)
                .defaultSize(width: 400, height: 400)
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

        // Clear existing provider references
        appState.stopTracking()
        arViewModel.isSyncedToImage = false // Reset sync flags
        arViewModel.isSyncedToObject = false

        if currentMode == .imageTarget {
            // --- Image Target Mode ---
            let referenceImages = ReferenceImage.loadReferenceImages(inGroupNamed: "SharedAnchors")
            if referenceImages.isEmpty {
                print("Error: Failed to load any reference images from group 'SharedAnchors'")
                appState.alertItem = AlertItem(title: "Error", message: "Could not load Image Target resources. Switching back to World Sync.")
                arViewModel.currentSyncMode = .world
                await configureARSession() // Reconfigure for world mode
                return
            }
            print("Loaded \(referenceImages.count) reference images for Image Target mode.")
            let imageProvider = ImageTrackingProvider(referenceImages: referenceImages)
            providers.append(imageProvider)
            appState.startImageTracking(provider: imageProvider) // Use updated AppState method

        } else if currentMode == .objectTarget {
            // --- Object Target Mode ---
            var referenceObject: ReferenceObject?
            var loadedURL: URL?
            
            // Add diagnostic logging to check bundle contents
            print("[visionOS] Diagnosing reference object issue:")
            let resourceURLs = Bundle.main.urls(forResourcesWithExtension: "referenceobject", subdirectory: nil) ?? []
            print("[visionOS] Found \(resourceURLs.count) .referenceobject files in bundle: \(resourceURLs.map { $0.lastPathComponent })")
            
            // Try different approaches to locate the reference object
            
            // Approach 1: Models subdirectory using url(forResource:)
            if let objectURL = Bundle.main.url(forResource: "model-mobile", withExtension: "referenceobject", subdirectory: "models") {
                print("[visionOS] Found reference object at: \(objectURL)")
                do {
                    referenceObject = try await ReferenceObject(from: objectURL)
                    loadedURL = objectURL
                    print("[visionOS] Successfully loaded reference object from models subdirectory.")
                } catch {
                    print("[visionOS] Info: Failed to load reference object from models subdirectory: \(error.localizedDescription). Trying main bundle.")
                    referenceObject = nil // Ensure it's nil if loading failed
                }
            } else {
                print("[visionOS] Reference object not found in models subdirectory")
            }

            // Approach 2: Main bundle using url(forResource:)
            if referenceObject == nil, let objectURL = Bundle.main.url(forResource: "model-mobile", withExtension: "referenceobject") {
                print("[visionOS] Found reference object in main bundle at: \(objectURL)")
                do {
                    referenceObject = try await ReferenceObject(from: objectURL)
                    loadedURL = objectURL
                    print("[visionOS] Successfully loaded reference object from main bundle.")
                } catch {
                    print("[visionOS] Error: Failed to load reference object from main bundle: \(error.localizedDescription)")
                    referenceObject = nil // Ensure it's nil if loading failed
                }
            } else if referenceObject == nil {
                print("[visionOS] Reference object not found in main bundle")
            }
            
            // Approach 3: Try using path(forResource:) which might handle spaces differently
            if referenceObject == nil, let objectPath = Bundle.main.path(forResource: "model-mobile", ofType: "referenceobject", inDirectory: "models") {
                let objectURL = URL(fileURLWithPath: objectPath)
                print("[visionOS] Found reference object using path API at: \(objectURL)")
                do {
                    referenceObject = try await ReferenceObject(from: objectURL)
                    loadedURL = objectURL
                    print("[visionOS] Successfully loaded reference object using path API.")
                } catch {
                    print("[visionOS] Error: Failed to load reference object using path API: \(error.localizedDescription)")
                    referenceObject = nil
                }
            } else if referenceObject == nil {
                print("[visionOS] Reference object not found using path API")
            }
            
            // Approach 4: Try searching for any reference object if the exact name fails
            if referenceObject == nil, let firstObjectURL = resourceURLs.first {
                print("[visionOS] Attempting to load alternative reference object: \(firstObjectURL.lastPathComponent)")
                do {
                    referenceObject = try await ReferenceObject(from: firstObjectURL)
                    loadedURL = firstObjectURL
                    print("[visionOS] Successfully loaded alternative reference object.")
                } catch {
                    print("[visionOS] Error: Failed to load alternative reference object: \(error.localizedDescription)")
                    referenceObject = nil
                }
            }

            // Check if loading ultimately failed
            guard let finalReferenceObject = referenceObject else {
                print("[visionOS] Error: Failed to load reference object 'model-mobile.referenceobject' from any location.")
                print("[visionOS] Bundle path: \(Bundle.main.bundlePath)")
                appState.alertItem = AlertItem(title: "Error", message: "Could not load Object Target resources. Switching back to World Sync.")
                arViewModel.currentSyncMode = .world
                await configureARSession() // Reconfigure for world mode
                return
            }

            print("Loaded reference object: \(finalReferenceObject.name ?? "Unnamed") from \(loadedURL?.path ?? "Unknown Path")")

            let objectProvider = ObjectTrackingProvider(referenceObjects: [finalReferenceObject])
            providers.append(objectProvider)
            appState.startObjectTracking(provider: objectProvider) // Use updated AppState method
        }
        // Else: World mode needs no extra provider beyond WorldTrackingProvider

        do {
            // Stop session before running with new providers
            session.stop()
            try await session.run(providers)
            print("ARKitSession running with providers: \(providers.map { type(of: $0) })")
            // Start monitoring based on the current mode AFTER session starts
            if currentMode == .imageTarget {
                await startImageMonitoring()
            } else if currentMode == .objectTarget {
                await startObjectMonitoring() // Start object monitoring
            }
        } catch {
            print("Error running ARKitSession: \(error)")
            appState.alertItem = AlertItem(title: "AR Error", message: "Failed to start AR Session: \(error.localizedDescription)")

            // Fallback to world mode if image/object tracking fails
            if arViewModel.currentSyncMode == .imageTarget || arViewModel.currentSyncMode == .objectTarget {
                arViewModel.currentSyncMode = .world
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

    // MARK: - Object Anchor Monitoring
    @MainActor
    func startObjectMonitoring() async {
        let currentMode = arViewModel.currentSyncMode
        let provider = appState.objectTrackingProvider // Get object provider from AppState

        guard currentMode == .objectTarget, let objectProvider = provider else {
            print("Not starting object monitoring (Mode: \(currentMode.rawValue), Provider: \(provider == nil ? "nil" : "exists"))")
            appState.isObjectTracked = false // Ensure state is false if not monitoring
            return
        }

        print("Starting Object Anchor monitoring...")

        Task {
            do {
                try Task.checkCancellation()

                for await anchorUpdate in objectProvider.anchorUpdates {
                    // Check mode again in case it changed
                    if arViewModel.currentSyncMode != .objectTarget {
                        print("Object Anchor Task: Exiting, mode changed during anchor update.")
                        break // Exit loop
                    }

                    let objectAnchor = anchorUpdate.anchor
                    let event = anchorUpdate.event
                    let objectName = objectAnchor.referenceObject.name ?? "Unknown Object"

                    switch event {
                    case .added, .updated:
                        if objectAnchor.isTracked {
                            // Object is currently tracked
                            if !arViewModel.isSyncedToObject {
                                // Perform the one-time sync alignment
                                let newWorldTransform = objectAnchor.originFromAnchorTransform
                                arViewModel.sharedAnchorEntity.setTransformMatrix(newWorldTransform, relativeTo: nil)
                                arViewModel.isSyncedToObject = true // Mark as synced
                                appState.isObjectTracked = true // Mark as detected
                                print("✅ Object Target '\(objectName)' detected. Synced sharedAnchorEntity transform.")
                            } else {
                                // Already synced, just update detection status
                                if !appState.isObjectTracked {
                                    appState.isObjectTracked = true
                                    print("👀 Object Target '\(objectName)' re-detected (already synced).")
                                }
                            }
                        } else {
                            // Object is lost
                            if appState.isObjectTracked {
                                print("⚠️ Object Target '\(objectName)' lost tracking.")
                                appState.isObjectTracked = false
                                // DO NOT reset isSyncedToObject here - alignment persists
                            }
                        }
                    case .removed:
                        if appState.isObjectTracked || arViewModel.isSyncedToObject { // Check both flags
                            print("❌ Object Target '\(objectName)' anchor removed.")
                            appState.isObjectTracked = false
                            // DO NOT reset isSyncedToObject here
                        }
                    @unknown default:
                        print("Unhandled object anchor event: \(event)")
                    }
                } // End loop (anchorUpdates)
            } catch {
                print("Error occurred during object anchor monitoring: \(error)")
            }

            // Ensure detection state is false if task finishes or exits loop
            if appState.isObjectTracked {
                print("Object monitoring loop finished/exited, resetting detection state.")
                appState.isObjectTracked = false
            }
        }
    }
}
