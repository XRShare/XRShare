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
    @State private var observer: NSObjectProtocol? = nil
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                // Only add observer once
                if observer == nil {
                    observer = NotificationCenter.default.addObserver(
                        forName: Notification.Name("openWindow"),
                        object: nil,
                        queue: .main) { notification in
                            if let id = notification.userInfo?["id"] as? String {
                                // Track opened windows with a timestamp to prevent duplicates
                                let timestamp = notification.userInfo?["timestamp"] as? Double ?? 0
                                
                                // Only process if not a duplicate notification
                                if timestamp > 0 {
                                    print("Opening window: \(id) at \(timestamp)")
                                    openWindow(id: id)
                                } else {
                                    openWindow(id: id)
                                }
                            }
                        }
                }
            }
            .onDisappear {
                // Properly remove observer when view disappears
                if let observer = observer {
                    NotificationCenter.default.removeObserver(observer)
                    self.observer = nil
                }
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
