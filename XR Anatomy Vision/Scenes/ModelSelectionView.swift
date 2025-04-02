import SwiftUI
import RealityKit

struct ModelSelectionScreen: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    @ObservedObject var modelManager: ModelManager

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    
    @State private var showingPopover = false
    @State var modelList: [String] = ["Anatomy Models", "Car Models", "Airplane Models", "Bird Models", "Food Models"]

    var body: some View {
        VStack(spacing: 20) {
            
            HStack(alignment: .top){
                Button("Back to Main") {
                    
                    dismissWindow(id: "AddModelWindow")
                    dismissWindow(id: "InSessionView")
                    
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
                
                Text("XRShare")
                    .font(.largeTitle)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 0){
                
                Button("Add a model"){
                    print("add a model selected")
                    dismissWindow(id: "AddModelWindow")
                    showingPopover = true
                }
                .background(RoundedRectangle(cornerRadius:30).fill(Color.white.opacity(0.6)))
                .sheet(isPresented: $showingPopover){
                    VStack{
                        Text("Select Type of Model:")
                            .padding()
                            .padding(.top, 10)
                            .font(.headline)
                            .bold()
                        
                        ForEach(modelList, id: \.self){ item in
                            Button(action:{
                                switch item{
                                case "Anatomy Models":
                                    appModel.selectedCategory = .anatomy
                                    openWindow(id: "AddModelWindow")
                                case "Food Models":
                                    appModel.selectedCategory = .food
                                    openWindow(id: "AddModelWindow")
                                default:
                                    break
                                }
                                
                                showingPopover = false
                                
                            }){
                                Text(item)
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            
                        }
                        .padding()
                        
                    }
                }
            }
                
        }
            .padding(35)
        

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
                    .padding(.horizontal)
                    .frame(height:50)
                    .background(Color.white.opacity(0.3))
                    .listRowInsets(EdgeInsets())
                    .cornerRadius(13)
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            
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
