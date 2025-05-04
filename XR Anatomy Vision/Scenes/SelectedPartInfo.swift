import SwiftUI
import RealityKit
import RealityKitContent

struct SelectedPartInfoScreen: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    @ObservedObject var modelManager: ModelManager
    
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    
    @State var title: String
    
    var body: some View{
        
                VStack(alignment: .leading, spacing: 12) {
                    
                        Text("Model part selected: \(title)")
                            .font(.title)
                            .padding(.leading, 12)
                        
                
                        
                        if let partInfo = modelManager.selectedPartInfo {
                            Text(partInfo)
                                .font(.body)
                                .padding(.bottom, 12)
                        } else {
                            Text("No information on part selected.")
                                .foregroundColor(.secondary)
                                .padding(.leading, 12)
                    }

                }
                .padding()
        
        
            }
        }
    
