import SwiftUI
import RealityKit

struct ModelSelectionScreen: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    @ObservedObject var modelManager: ModelManager

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        VStack(spacing: 20) {
            
            HStack{
                Button("Back to Main") {
                    // Clear models
                    modelManager.reset()
                    // Reset multipeer services
                    arViewModel.stopMultipeerServices()
                    // Exit the immersive view
                    Task {
                        await dismissImmersiveSpace()
                    }
                    // Switch the app page back to main
                    appModel.currentPage = .mainMenu
                }
                .background(RoundedRectangle(cornerRadius:30).fill(Color.white.opacity(0.3)))
                
                Spacer()
                
                Text("Session Name:")
                    .font(.largeTitle)
                
                Spacer()
                
                Button("Add a model"){
                    print("add a model selected")
                    openWindow(id: "AddModelWindow")
                }
                .background(RoundedRectangle(cornerRadius:30).fill(Color.white.opacity(0.6)))
                
                
            }
            .padding(35)
            
            
            ScrollView {
                ForEach(modelManager.modelTypes, id: \.id) { modelType in
                    Button(modelType.rawValue) {
                        modelManager.loadModel(for: modelType, arViewModel: arViewModel)
                    }
                }
            }
            .frame(height: 200)

            Text("Loaded Models: \(modelManager.placedModels.count)")

            List {
                ForEach(modelManager.placedModels, id: \.id) { mod in
                    HStack {
                        Text(mod.modelType.rawValue)
                        Spacer()
                        Button("Delete") {
                            modelManager.removeModel(mod)
                        }
                    }
                }
            }
            
            HStack {
                
                Spacer()
                
                // Debug mode toggle with manual action to handle MainActor requirements
                Button(action: {
                    // Debounce to prevent multiple toggles
                    guard !appModel.controlPanelVisible || !appModel.debugModeEnabled else { 
                        print("Debug panel already visible")
                        return 
                    }
                    
                    // Toggle debug mode with UI update
                    appModel.toggleDebugModeUI()
                }) {
                    Label(
                        appModel.debugModeEnabled ? "Debug Console: Open" : "Debug Console: Closed", 
                        systemImage: "ladybug"
                    )
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(appModel.debugModeEnabled ? .green : .blue)
                .disabled(appModel.controlPanelVisible && appModel.debugModeEnabled)
                
                .onAppear {
                    Task {
                        _ = await openImmersiveSpace(id: appModel.immersiveSpaceID)
                    }
                }
            }
            .padding()
        }
        .background((Color.black).opacity(0.2))
        .cornerRadius(30)
        .onAppear {
            modelManager.loadModelTypes()
        }
        .onDisappear {
            // Also clear if user navigates away via system or other route
            modelManager.reset()
            arViewModel.stopMultipeerServices()
            Task {
                await dismissImmersiveSpace()
            }
        }
    }
}

struct ModelSelectionView : PreviewProvider {
    static var previews: some View {
        ModelSelectionScreen(modelManager : ModelManager())
            .environmentObject(AppModel())
            .environmentObject(ARViewModel())
    }
    
}
