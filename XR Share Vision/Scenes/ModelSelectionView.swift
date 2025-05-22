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
            
            HStack{
                Button("Back to Main") {
                    
                    dismissWindow(id: "AddModelWindow")
                    dismissWindow(id: "InSessionView")
                    
                    // Clear models
                    modelManager.reset()
                    // Reset multipeer services
                    arViewModel.stopMultipeerServices()
                    // Exit the immersive view only if it's open
                    Task {
                        if appModel.immersiveSpaceState == .open {
                            await dismissImmersiveSpace()
                        }
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
                    
                    // Use the unique instanceUUID for the ForEach identifier
                ForEach(modelManager.placedModels, id: \.instanceUUID) { mod in
                        HStack(spacing: 12) {
                            
                            Text(mod.modelType.rawValue)
                                .padding(.horizontal, 16)
                                .frame(height: 44)
                                .foregroundColor(.white)
                            
                            Spacer()
                        
                            // Users can select to get brief description of the model
                            HStack(spacing: 12){
                                Button(action: {
                                    print("Info Selected")
                                    modelManager.isInfoModeActive.toggle()
                                }) {
                                    Image(systemName: "hand.tap")
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                                
                                
                                // After selecting, users can select part of model to get more information about it
                                Button(action: {
                                    print("more info Selected")
                                    dismissWindow(id: "ModelInfoWindow")
                                    modelManager.selectedModelInfo = mod.modelType.rawValue
                                    openWindow(id: "ModelInfoWindow" )
                                }) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                                
                                
                                Button(action: {
                                    print("trash Selected")
                                    modelManager.removeModel(mod)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                                
                            }
                            .padding(.horizontal, 20)
                            .frame(height:44)
                            
                        }
                        .frame(height:50)
                        .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.3)))
                        .padding(.horizontal)
                        
                    }
            
            // Add tag to help identify the list causing the warning if it persists
            .id("PlacedModelsList")

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
            Spacer()
        }
        .cornerRadius(30)
        .onAppear {
            modelManager.loadModelTypes()
        }
        .onDisappear {
            // Only reset when actually leaving the session (going back to main menu)
            if appModel.currentPage == .mainMenu {
                modelManager.reset()
                arViewModel.stopMultipeerServices()
                Task {
                    if appModel.immersiveSpaceState == .open {
                        await dismissImmersiveSpace()
                    }
                }
            }
        }
    }
}
        
