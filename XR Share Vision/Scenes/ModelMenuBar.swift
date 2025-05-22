//
//  ModelMenuBar.swift
//  XR Share Vision
//
//  Created by Joanna  Lin  on 2025-05-20.
//



import SwiftUI
import RealityKit

struct ModelMenuBar: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    @ObservedObject var modelManager: ModelManager
    
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    
    
    @State private var heartTitle = "Heart"
    @State private var description = "The human heart is a muscular organ about the size of a fist that pumps blood throughout the body. It has four chambers: two atria (upper) and two ventricles (lower)."
    
    @State private var arteriesTitle = "Arteries Head"
    @State private var arteriesDescription = "The arteries in the head mainly stem from the common carotid and vertebral arteries. The internal carotid arteries supply the brain and eyes, while the external carotid arteries serve the face and scalp."
    
    
    @State private var pancakesTItle = "Panackes"
    @State private var pancakesDescription = "Pancakes with blueberries are a delicious and comforting breakfast treat. Fluffy and golden, the pancakes are often made with a simple batter of flour, eggs, milk, and baking powder."
    
    var mostRecentlyPlacedModel: Model? {
        modelManager.placedModels.last
    }
    
    
    
    var body: some View {
        
        VStack{
        
            if let mod = mostRecentlyPlacedModel {
                HStack(spacing: 12) {
                    
                    VStack{
                        
                        Text(mod.modelType.rawValue)
                            .font(.title)
                            .frame(height: 44)
                            .foregroundColor(.white)
                        
                        
                        if modelManager.modelInfoSelected == false {
                            Text("Anatomy Model")
                                .font(.subheadline)
                        }
                        
                    }
                    
                    if modelManager.modelInfoSelected {
                        
                        if modelManager.selectedModelInfo == "Heart"{
                            
                            Text(description)
                        }
                        
                        if modelManager.selectedModelInfo == "ArteriesHead"{
                            
                            Text(arteriesDescription)
                            
                        }
                        
                        if modelManager.selectedModelInfo == "pancakes"{
                            
                            Text(pancakesDescription)
                        }
                        
                    }
                    
                }
                .padding(.horizontal)
            }
        }
        .ornament(
            visibility: .visible,
            attachmentAnchor: .scene(.bottom),
            contentAlignment: .center
        ){
            
            if let mod = mostRecentlyPlacedModel {
                
                HStack(spacing: 5){
                    
                    
                    Button(action: {
                        print("more info Selected")
                        modelManager.selectedModelInfo = mod.modelType.rawValue
                        modelManager.modelInfoSelected.toggle()
                    }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 80, height: 50)
                    .padding([.top, .bottom])
                    
                    
                    
                    Button(action: {
                        print("Info Selected")
                        modelManager.isInfoModeActive.toggle()
                    }) {
                        Image(systemName: "hand.tap")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 80, height: 50)
                    .padding([.top, .bottom])
                    
                    
                    Button(action: {
                        print("trash Selected")
                        modelManager.removeModel(mod)
                        dismissWindow(id: "ModelMenuBar")
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 80, height: 50)
                    .padding([.top, .bottom])
                    
                    
                    Button(action: {
                        print("Speak selected")
                    }) {
                        Image(systemName: "speaker.wave.3")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 80, height: 50)
                    .padding([.top, .bottom])
                    
                }
                .labelStyle(.iconOnly)
                .padding(.horizontal)
                .glassBackgroundEffect()
                
                
            }
            
        }
        }
        
    }

