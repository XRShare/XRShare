// UI related stuff: UIView and the views it references
// These define how the app looks, but also contain some logic controlling how the user moves from one view to another

import SwiftUI
import RealityKit
import ARKit

// The main UI container that holds the different Views, for the most part:
struct UIView: View {
    @StateObject var arViewModel = ARViewModel()
    @State private var showModelMenu = false
    @State private var showResetConfirmation = false
    @State private var showSettingsOptions = false
    @State private var isFirstLaunchLoading = false
    @State private var loadingProgress: Float = 0.0
    @State private var hasStartedMultipeer = false
    @State private var showSplashScreen = !AppLoadTracker.hasRestarted
    @State private var hasSelectedMode = false // Track mode selection

    var body: some View {
        ZStack {
            if showSplashScreen {
                LoadingView(loadingProgress: $loadingProgress, showProgress: false)  // only shows on first build from Xcode
            } else if isFirstLaunchLoading {
                LoadingView(loadingProgress: $loadingProgress)  // ^ same
            } else if !hasSelectedMode {  //
                StartupMenuView(hasSelectedMode: $hasSelectedMode)
                    .environmentObject(arViewModel)
            } else {
                ZStack(alignment: .top) {
                    ARViewContainer(onSwipeFromLeftEdge: handleSwipeFromLeftEdge)
                        .edgesIgnoringSafeArea(.all)
                        .environmentObject(arViewModel)

                    
                    // LEFT SIDE OF SCREEN UI elements
                    VStack {
                        Spacer() // Pushes the button to the bottom
                        HStack {
                            Button(action: handleBackButtonTap) {
                                Image(systemName: "arrowshape.left")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    // some extra space around it that will register a tap
                                    .contentShape(Circle())
                                    .padding(10)
                            }
                            //Spacer() // use to push any other items here to the right
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.leading, -10)
                    .padding(.bottom, -20) // move it a little lower, below where Apple wants you place things

                    
                    // CENTER of screen UI elements
                    VStack {
                        ConnectionStatusView()
                            .environmentObject(arViewModel)
                            .padding(.top, -5)
                            .frame(maxWidth: .infinity, alignment: .center)
                        Spacer()
                    }

                    
                    // RIGHT SIDE OF SCREEN UI elements
                    // Conditionally show these buttons based on user role / permissions granted by Host
                    if arViewModel.userRole != .viewer || arViewModel.isHostPermissionGranted {
                        VStack(spacing: 10) {
                            // Model menu button
                            Button(action: { showModelMenu.toggle() }) {
                                Image(systemName: "figure")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    // some extra space around it that will register a tap
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
                            
                            // Delete models button
                            Button(action: { showResetConfirmation = true }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    // some extra space around it that will register as a tap
                                    .contentShape(Circle())
                                    .padding(5)
                            }
                            .padding(.bottom, 190)
                            
                            // toggle button to give host permissions/controls to Viewers (only ever show for Host)
                            if arViewModel.userRole == .host {
                                Button(action: {
                                    arViewModel.toggleHostPermissions()
                                }) {
                                    Image(systemName: arViewModel.isHostPermissionGranted ? "lock.open" : "lock")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .padding(10)
                                        // some extra space around it that will register as a tap
                                        .contentShape(Circle())
                                        .padding(10)
                                }
                                .padding(.bottom, 0)
                            }
                            
                            // Debug menu button
                            Button(action: { showSettingsOptions.toggle() }) {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    // some extra space around it that will register as a tap
                                    .contentShape(Circle())
                                    .padding(10)
                            }
                            .padding(.bottom, -10)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, -10) // from the right edge of screen
                        .padding(.bottom, -10) // move it a little lower, below where Apple wants you place things
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
                        primaryButton: .destructive(Text("Delete")) { arViewModel.clearAllModels() },
                        secondaryButton: .cancel()
                    )
                }
            }
        }
        .onAppear {
            handleInitialLaunch()
        }
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
            if session != nil {
                hasSelectedMode = true
            }
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
        hasSelectedMode = false // Return to the main menu
    }
    
    private func handleSwipeFromLeftEdge() {
        handleBackButtonTap() // do the same thing
    }
    
}



//  These could each be their own .swift file, but they can stay here for now for simplicity ----------
//  They are all UI related and only used by the Views in this file, ...mostly.
struct LoadingView: View {
    @Binding var loadingProgress: Float
    var showProgress: Bool = true // Add a flag to toggle the ProgressView

    var body: some View {
        ZStack {
            Color(red: 0.9137, green: 0.9176, blue: 0.9255) // Background color
                .edgesIgnoringSafeArea(.all) // Make it cover the entire screen

            VStack(spacing: 20) {
                Image("logo_white")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 360)
                    .padding(.top, 40)

                Text("Preparing your AR experience...")
                    .font(Font.custom("Courier New", size: 18))
                    .foregroundColor(.black)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top, 35)

                if showProgress {
                    ProgressView(value: loadingProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(width: 200)
                        .padding(.top, 20)
                        .tint(.black)

                    if loadingProgress < 1.0 {
                        Text("Loading models and initializing AR...")
                            .font(Font.custom("Courier New", size: 14))
                            .foregroundColor(.black)
                            .padding(.top, 10)
                    }
                }

                Spacer()
            }
            .padding()
        }
        .onAppear {
            OrientationManager.shared.lock(to: .portrait)
        }
    }
}


struct StartupMenuView: View {
    @Binding var hasSelectedMode: Bool
    @EnvironmentObject var arViewModel: ARViewModel
    @State private var isJoiningSession = false
    @State private var isEnteringSessionName = false
    @State private var sessionNameInput: String = ""
    let bgColor = Color(red: 0.9137, green: 0.9176, blue: 0.9255)
    let pressedButtonColor = Color(red: 0.8, green: 0.8, blue: 0.8)

    var body: some View {
        GeometryReader { metrics in
            ZStack {
                bgColor
                    .edgesIgnoringSafeArea(.all)

                VStack(spacing: 20) {
                    Image("logo_white")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 360)
                        .padding(.top, 40)
                        .padding(.bottom, 30)

                    Spacer()

                    if isJoiningSession {
                        Text("Available Sessions:")
                            .font(.title2)
                            .foregroundColor(.black)
                            .padding()

                        List(arViewModel.availableSessions, id: \.sessionID) { session in
                            Button(action: {
                                // from older version (that works, lol)
                                arViewModel.selectedSession = session
                                arViewModel.invitePeer(session.peerID, sessionID: session.sessionID) // BLAH... might not be needed
                                
                                arViewModel.sessionID = session.sessionID
                                arViewModel.sessionName = session.sessionName
                                arViewModel.userRole = .viewer
                                arViewModel.pendingPeerToConnect = session.peerID  // Store peerID
                                arViewModel.connectToSession(peerID: session.peerID)
                                hasSelectedMode = true  // This will initialize arView
                            }) {
                                Text((session.sessionName.isEmpty ? "" : "Session: " + session.sessionName))
                            }
                        }
                        .listStyle(PlainListStyle())
                        .frame(maxWidth: .infinity)
                        .padding()
                        
                        Spacer()
                        
                        // cancel button to back out of the Join session menu
                        Button(action: {
                            isJoiningSession = false
                        }) {
                            Text("Cancel")
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .foregroundColor(.red)
                                .background(bgColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9)
                                        .stroke(Color.black, lineWidth: 2)
                                )
                        }
                        .padding()
                        
                    } else {
                        ForEach(["Host session", "Join session"], id: \.self) { title in  // , "Collaborate"
                            Button(action: {
                                switch title {
                                case "Host session":
                                    isEnteringSessionName = true // Show the session name input modal
                                case "Join session":
                                    arViewModel.userRole = .viewer
                                    arViewModel.startMultipeerServices()
                                    isJoiningSession = true
//                                case "Collaborate":  // not using this atm. Uses collaboration mode instead of world maps...
//                                    arViewModel.userRole = .openSession
//                                    arViewModel.sessionID = UUID().uuidString
//                                    print("Collaborate session with sessionID: \(arViewModel.sessionID)")
//                                    arViewModel.startMultipeerServices()
//                                    hasSelectedMode = true
                                default:
                                    break
                                }
                            }) {
                                Text(title)
                                    .font(.title2)
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity, minHeight: 25)
                                    .padding()
                                    //.background(Color(red: tintLevel, green: tintLevel, blue: tintLevel))
                            }
                            .padding(.bottom, 2)
                            .buttonStyle(PressableButtonStyle(normalColor: bgColor, pressedColor: pressedButtonColor))
                        }
                    }
                }
                .padding()
                // Present the SessionNameInputAlert as an overlay
                if isEnteringSessionName {
                    SessionNameInputAlert(
                        isPresented: $isEnteringSessionName,
                        sessionName: $sessionNameInput,
                        onContinue: {
                            arViewModel.sessionName = sessionNameInput
                            arViewModel.userRole = .host
                            arViewModel.sessionID = UUID().uuidString
                            print("Host session with sessionID: \(arViewModel.sessionID) and sessionName: \(arViewModel.sessionName)")
                            arViewModel.startMultipeerServices()
                            hasSelectedMode = true
                        }
                    )
                }
            }
        }
        .onAppear {
            OrientationManager.shared.lock(to: .portrait)
            if arViewModel.userRole == .viewer {
                arViewModel.availableSessions = [] // hmmm...
                arViewModel.startMultipeerServices()
            }
        }
        .onDisappear {
            OrientationManager.shared.unlock()
        }
    }
}

struct PressableButtonStyle: ButtonStyle {
    let normalColor: Color
    let pressedColor: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? pressedColor : normalColor)
            .cornerRadius(9)
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(Color.black, lineWidth: 2)
            )
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}




struct SessionNameInputAlert: View {
    @Binding var isPresented: Bool
    @Binding var sessionName: String
    var onContinue: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    // Optionally dismiss when tapping outside
                    isPresented = false
                }

            // Centered alert view
            VStack(spacing: 16) {
                Text("Enter Session Name")
                    .font(.headline)
                    .padding(.top, 16)

                TextField("Session Name", text: $sessionName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    .focused($isTextFieldFocused)
                    .submitLabel(.done)

                Divider()

                HStack {
                    Button(action: {
                        isPresented = false
                    }) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.red)
                    }
                    .padding()

                    Button(action: {
                        isPresented = false
                        onContinue()
                    }) {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .disabled(sessionName.isEmpty)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 20)
            .frame(maxWidth: 300)
            .onAppear {
                isTextFieldFocused = true
            }
        }
    }
}



// displays at the middle of the top of the screen when viewing AR content...
struct ConnectionStatusView: View {
    @EnvironmentObject var arViewModel: ARViewModel

    var body: some View {
        VStack {
            if arViewModel.connectedPeers.isEmpty {
                Text("Searching for peers...")
                    .padding(8)
                    .background(Color.yellow.opacity(0.8))
                    .cornerRadius(8)
            } else {
                Text("Connected to \(arViewModel.connectedPeers.count) peer(s)")
                    .padding(8)
                    .background(Color.green.opacity(0.8))
                    .cornerRadius(8)
            }
        }
        .padding()
    }
}



// Used for housing the Settings menu's view, SettingsView (defined below)
struct BottomSheet<Content: View>: View {
    var content: Content
    private let heightFraction: CGFloat = 0.67 // Customize the height fraction. Increase it if you need more space (up to 1.0)

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()
                VStack {
                    content
                }
                .frame(width: geometry.size.width, height: geometry.size.height * heightFraction)
                .background(Color(.systemBackground).opacity(0.7))
                .cornerRadius(16)
                .shadow(radius: 8)
            }
            .edgesIgnoringSafeArea(.bottom)
        }
    }
}



struct SettingsView: View {
    @Binding var isVisible: Bool
    @ObservedObject var arViewModel: ARViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.headline)
                .padding(.top)
            
            Toggle("Plane Visualization", isOn: $arViewModel.isPlaneVisualizationEnabled)
            Toggle("Feature Points", isOn: $arViewModel.areFeaturePointsEnabled)
            Toggle("World Origin", isOn: $arViewModel.isWorldOriginEnabled)
            Toggle("Anchor Origins", isOn: $arViewModel.areAnchorOriginsEnabled)
            Toggle("Anchor Geometry", isOn: $arViewModel.isAnchorGeometryEnabled)
            Toggle("Scene Understanding", isOn: $arViewModel.isSceneUnderstandingEnabled)
            
                .onChange(of: arViewModel.isPlaneVisualizationEnabled) { isEnabled in
                    arViewModel.togglePlaneVisualization(isEnabled: isEnabled)
                }

            Spacer()
            
            Button(action: {
                isVisible = false // Dismiss the overlay
            }) {
                Text("Close")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}


struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}



// These 3 used for enforcing portrait lock on the main menu views... it's not perfect. Hard to get orientation lock working, surprisingly.
class OrientationManager {
    static let shared = OrientationManager()
    private init() {}

    var orientationLock: UIInterfaceOrientationMask = .all

    func lock(to orientation: UIInterfaceOrientationMask) {
        orientationLock = orientation
        UIDevice.current.setValue(
            orientation == .portrait ? UIInterfaceOrientation.portrait.rawValue : UIInterfaceOrientation.unknown.rawValue,
            forKey: "orientation"
        )
    }

    func unlock() {
        lock(to: .all)
    }
}
class PortraitHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    override var shouldAutorotate: Bool {
        return false
    }
}
struct PortraitLockedView<Content: View>: UIViewControllerRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        return PortraitHostingController(rootView: content)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
