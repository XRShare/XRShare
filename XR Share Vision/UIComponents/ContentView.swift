import SwiftUI

// Utility for window management - centralized control
class WindowManager {
    static let shared = WindowManager()
    
    // Safe method to request a window to be opened - can be called from any context
    func requestWindowOpen(id: String) {
        let name = id.replacingOccurrences(of: "Panel", with: " Panel")
        print("Requesting to open \(name)")
        
        // Use Task to ensure we're on the main actor when posting notifications
        Task { @MainActor in
            // Post notification to any listeners
            NotificationCenter.default.post(
                name: Notification.Name("openWindow"), 
                object: nil, 
                userInfo: ["id": id]
            )
        }
    }
}

// Reusable UI components
struct ControlButton: View {
    var label: String
    var systemImage: String
    var color: Color = .blue
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .font(.caption)
                .padding(8)
                .background(color)
                .cornerRadius(8)
                .foregroundColor(.white)
        }
    }
}

// For panel headers and common styles
struct PanelHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }
}

extension View {
    func panelHeader() -> some View {
        self.modifier(PanelHeaderStyle())
    }
}

// Reusable window opener modifier with proper lifecycle management
struct WindowOpenerModifier: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var openObserver: NSObjectProtocol? = nil
    @State private var closeObserver: NSObjectProtocol? = nil
    // Store last opened window ID and timestamp
    @State private var lastOpenedWindowId: String? = nil
    @State private var lastOpenedTimestamp: Double = 0.0
    // Debounce interval (e.g., 1 second)
    private let debounceInterval: Double = 1.0

    func body(content: Content) -> some View {
        content
            .onAppear {
                if openObserver == nil {
                    openObserver = NotificationCenter.default.addObserver(
                        forName: Notification.Name("openWindow"),
                        object: nil,
                        queue: .main) { notification in
                            guard let id = notification.userInfo?["id"] as? String,
                                  let timestamp = notification.userInfo?["timestamp"] as? Double else {
                                return
                            }

                            // Check if this is a duplicate request within the debounce interval
                            if id == lastOpenedWindowId && (timestamp - lastOpenedTimestamp) < debounceInterval {
                                print("Debounced duplicate request to open window: \(id)")
                                return // Ignore duplicate
                            }

                            // Update last opened info and open the window
                            print("Opening window: \(id) at \(timestamp)")
                            lastOpenedWindowId = id
                            lastOpenedTimestamp = timestamp
                            openWindow(id: id)
                        }
                }
                
                // Add close window observer
                if closeObserver == nil {
                    closeObserver = NotificationCenter.default.addObserver(
                        forName: Notification.Name("closeWindow"),
                        object: nil,
                        queue: .main) { notification in
                            guard let id = notification.userInfo?["id"] as? String else {
                                return
                            }
                            print("Closing window: \(id)")
                            dismissWindow(id: id)
                        }
                }
            }
            .onDisappear {
                if let openObserver = openObserver {
                    NotificationCenter.default.removeObserver(openObserver)
                    self.openObserver = nil
                }
                if let closeObserver = closeObserver {
                    NotificationCenter.default.removeObserver(closeObserver)
                    self.closeObserver = nil
                }
                // Reset state on disappear
                lastOpenedWindowId = nil
                lastOpenedTimestamp = 0.0
            }
    }
}

// Extension to make it easier to use
extension View {
    func withWindowOpener() -> some View {
        self.modifier(WindowOpenerModifier())
    }
}

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    @ObservedObject var modelManager: ModelManager
    
    var body: some View {
        
        ZStack{
        
        switch appModel.currentPage{
        case .mainMenu:
            MainMenu()
            
        case .modelSelection:
            EmptyView()
        }
    }
        .onChange(of: appModel.currentPage){_, newPage in
            if newPage == .modelSelection{
                openWindow(id: "InSessionView")
            }
            
        }
    }
}
