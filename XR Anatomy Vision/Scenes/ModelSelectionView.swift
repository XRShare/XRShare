import SwiftUI
import RealityKit

struct ModelSelectionScreen: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    @ObservedObject var modelManager: ModelManager
    
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select Your Models")
                .font(.largeTitle)
            
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
                Button("Back to Main") {
                    modelManager.reset()
                    appModel.currentPage = .mainMenu
                }
                
                Spacer()
                
                Button("Enter Immersive") {
                    Task {
                        let result = await openImmersiveSpace(id: appModel.immersiveSpaceID)
                        if case .opened = result {
                            print("Immersive space opened")
                        } else {
                            print("ImmersiveSpace open failed or canceled.")
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            modelManager.loadModelTypes()
        }
    }
}
