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
                    // Exit the immersive view
                    Task {
                        await dismissImmersiveSpace()
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
            // Also clear if user navigates away via system or other route
            modelManager.reset()
            arViewModel.stopMultipeerServices()
            Task {
                await dismissImmersiveSpace()
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
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    
    func modelCard(for mod: Model) -> some View {
        VStack(spacing: 0) {
            Image("Heart") // Optionally replace with mod-specific thumbnail
                .resizable()
                .scaledToFit()
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipped()

            HStack {
                Text(mod.modelType.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .truncationMode(.tail)

                Spacer()

                Button(action: {
                    modelManager.removeModel(mod)
                    dismissWindow(id: "ModelMenuBar")
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button(action: {
                    openWindow(id: "ModelMenuBar")
                }) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.3))
        }
        .frame(width: 280, height: 160)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    
}



extension ModelCategory {
    var displayName: String {
        self.rawValue.capitalized + " Models"
    }
}




        
