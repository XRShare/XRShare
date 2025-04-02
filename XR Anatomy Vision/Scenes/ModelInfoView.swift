import SwiftUI
import RealityKit
import RealityKitContent

struct ModelInformationView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    @ObservedObject var modelManager: ModelManager
    
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    
    
    VStack{
        Text("Heart")
            .font(.headline)
        
        Text("The human heart is a muscular organ about the size of a fist that pumps blood throughout the body. It has four chambers: two atria (upper) and two ventricles (lower). The right side pumps oxygen-poor blood to the lungs, while the left side pumps oxygen-rich blood to the body. Valves within the heart ensure blood flows in one direction. Coordinated electrical signals regulate its rhythm, enabling continuous circulation of nutrients, oxygen, and waste removal.")
            .font(.body)
    }
