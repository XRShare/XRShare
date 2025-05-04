import SwiftUI
import RealityKit

struct ModelInformationView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    @ObservedObject var modelManager: ModelManager
    
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    
    @State private var heartTitle = "Heart"
    @State private var description = "The human heart is a muscular organ about the size of a fist that pumps blood throughout the body. It has four chambers: two atria (upper) and two ventricles (lower). The right side pumps oxygen-poor blood to the lungs, while the left side pumps oxygen-rich blood to the body. Valves within the heart ensure blood flows in one direction. Coordinated electrical signals regulate its rhythm, enabling continuous circulation of nutrients, oxygen, and waste removal."
    
    @State private var arteriesTitle = "Arteries Head"
    @State private var arteriesDescription = "The arteries in the head mainly stem from the common carotid and vertebral arteries. The internal carotid arteries supply the brain and eyes, while the external carotid arteries serve the face and scalp. The vertebral arteries travel through the neck to supply the brainstem and back of the brain. These vessels connect at the Circle of Willis, ensuring steady blood flow to the brain even if one artery is blocked."
    
    @State private var pancakesTItle = "Panackes"
    @State private var pancakesDescription = "Pancakes with blueberries are a delicious and comforting breakfast treat. Fluffy and golden, the pancakes are often made with a simple batter of flour, eggs, milk, and baking powder, with fresh or frozen blueberries mixed in or sprinkled on top. As they cook, the blueberries burst, adding a sweet, tangy flavor and a pop of color. They're often served with butter and maple syrup for a classic finish."
    
    var body: some View{
        VStack(alignment: .leading, spacing: 12){
            
        if modelManager.selectedModelInfo == "Heart"{
            Text(heartTitle)
                .font(.largeTitle)
                .padding(.leading, 12)
           
            
            Text(description)
                .font(.body)
                .padding(.leading, 12)
            
            
            }
        
        if modelManager.selectedModelInfo == "ArteriesHead"{
                Text(arteriesTitle)
                    .font(.largeTitle)
                    .padding(.leading, 12)
                
                Text(arteriesDescription)
                    .font(.body)
                    .padding(.leading, 12)
                
                }
            
        if modelManager.selectedModelInfo == "pancakes"{
            Text(pancakesTItle)
                .font(.largeTitle)
                .padding(.leading, 12)
                
            Text(pancakesDescription)
                .font(.body)
                .padding(.leading, 12)
                
                }
        
        }
        .padding()
        
    }
    
}


