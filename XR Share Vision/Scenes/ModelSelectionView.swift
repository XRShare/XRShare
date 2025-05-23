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
    
 
    @State var modelList: [String] = ["Anatomy Models", "Car Models", "Airplane Models", "Bird Models", "Food Models"]

    var body: some View {
        VStack(spacing: 20) {
            
            HStack{
                Button(action: {
                    
                    dismissWindow(id: "AddModelWindow")
                    dismissWindow(id: "InSessionView")
                    openWindow(id: "MainMenu")
                    
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
                    }) {
                        Image(systemName: "chevron.left")
                    }
                
                Spacer()
                
                Text("XRShare")
                    .font(.largeTitle)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 0){
                
                    Button(action: {
                    print("add a model selected")
                    dismissWindow(id: "AddModelWindow")
                    modelManager.showingPopover = true
                    }) {
                        Image(systemName: "plus")
                    }
                    
                    .sheet(isPresented: $modelManager.showingPopover){
                        VStack{
                            
                            HStack{
                                Button(action: {
                                    modelManager.showingPopover = false
                                }){
                                    Image(systemName: "xmark")
                                }
                                
                                Text("Select Type of Model:")
                                    .padding()
                                    .padding(.top, 10)
                                    .font(.headline)
                                    .bold()
                            }
                            .padding()
                            
                            ForEach(modelList, id: \.self){ item in
                                Button(action:{
                                    switch item{
                                    case "Anatomy Models":
                                        appModel.selectedCategory = .anatomy
                                        modelManager.showingPopover = false
                                        modelManager.showingModelPopover = true
                                    case "Food Models":
                                        appModel.selectedCategory = .food
                                        modelManager.showingPopover = false
                                        modelManager.showingModelPopover = true
                                    default:
                                        break
                                    }
                                    
                                }){
                                    Text(item)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                
                            }
                            .padding()
                        }
                    }
                    
                    .sheet(isPresented: $modelManager.showingModelPopover){
                        AddModelView(modelManager: modelManager)
                    }
            }
                
        }
            .padding(.horizontal,24)
            .padding(.top, 24)
            .padding(.bottom, 24)
            
            
            
            
            
            VStack{
                Text("Current Session Name")
                    .font(.title)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
                
                
                
                Text("Number of people in session: 0 ")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            
            Spacer()
            
            VStack{
                
                
                Text("Loaded Models: \(modelManager.placedModels.count)")
                    .font(.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
            
            
                    
                    // Use the unique instanceUUID for the ForEach identifier
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(ModelCategory.allCases) { category in
                        let modelsInCategory = models(for: category)

                        if !modelsInCategory.isEmpty {
                            modelRow(for: category, models: modelsInCategory)
                        }
                    }
                }
                .padding(.top)
            }

            
            // Add tag to help identify the list causing the warning if it persists
            .id("PlacedModelsList")

            HStack {
                
                Spacer()
                
                // Debug mode toggle with manual action to handle MainActor requirements
                Button(action: {
                    // Toggle debug mode
                    appModel.debugModeEnabled.toggle()
                    print("Debug mode \(appModel.debugModeEnabled ? "enabled" : "disabled")")
                    
                    if appModel.debugModeEnabled {
                        // Open debug window directly
                        openWindow(id: "controlPanel")
                        appModel.controlPanelVisible = true
                    } else {
                        // Close debug window
                        dismissWindow(id: "controlPanel")
                        appModel.controlPanelVisible = false
                    }
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
    
    
    func models(for category: ModelCategory) -> [Model] {
        modelManager.placedModels.filter {
            $0.modelType.category == category
        }
    }
    
    func modelRow(for category: ModelCategory, models: [Model]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.displayName)
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(models, id: \.instanceUUID) { mod in
                        modelCard(for: mod)
                            .animation(.easeInOut(duration: 0.3), value: models.count)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    
    func modelCard(for mod: Model) -> some View {
        VStack(spacing: 0) {
            // Enhanced model preview with 3D capability
            ZStack {
                // Background with glass effect
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.1))
                    }
                
                // Model preview - try 3D first, fallback to 2D
                Group {
                    if let entity = mod.modelEntity {
                        // Use Model3D for live 3D preview
                        Model3DPreviewView(modelEntity: entity)
                    } else {
                        // Fallback to 2D preview
                        ModelPreviewView(
                            modelType: mod.modelType,
                            size: CGSize(width: 100, height: 100)
                        )
                    }
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .clipped()

            // Enhanced control bar with spatial design
            HStack {
                Text(mod.modelType.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .truncationMode(.tail)

                Spacer()

                HStack(spacing: 8) {
                    Button(action: {
                        modelManager.removeModel(mod)
                        dismissWindow(id: "ModelMenuBar")
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.red.opacity(0.8))
                            .frame(width: 24, height: 24)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)

                    Button(action: {
                        openWindow(id: "ModelMenuBar")
                    }) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 24, height: 24)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.thinMaterial)
        }
        .frame(width: 300, height: 180) // Slightly larger for better proportions
        .background(.regularMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .hoverEffect(.lift)
    }

    
}



extension ModelCategory {
    var displayName: String {
        self.rawValue.capitalized + " Models"
    }
}




        
