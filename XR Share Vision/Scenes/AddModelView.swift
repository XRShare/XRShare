//
//  SwiftUIView.swift
//  XR Anatomy Vision
//
//  Created by Joanna  Lin  on 2025-03-23.
//

import SwiftUI
import RealityKit

struct AddModelView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    @ObservedObject var modelManager: ModelManager

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        VStack(spacing:0){
            
            HStack{
                Button(action:{
                    dismissWindow(id: "AddModelWindow")
                }){
                    Image(systemName: "xmark")
                        .frame(width:12, height:12)
                }
                
                Spacer()
                
                Text("Models")
                    .font(.title)
                
                Spacer()
                
                Color.clear.frame(width:12, height:12)
                
            }
            .padding(.top, 20)
            .padding(.bottom, 25)
            .padding(.horizontal)
            
            Spacer()
        
            if let selectedCategory = appModel.selectedCategory {
                List(modelManager.models(for: selectedCategory), id: \.id){  modelType in
                    Button{
                        modelManager.loadModel(for: modelType, arViewModel: arViewModel)
                    } label:{
                        HStack{
                            Text(modelType.rawValue)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(.white)
                            
                        }
                        .padding(.vertical, 8)
                    }
                    
                    .listRowBackground(Color.clear)
                    
                }
                .listStyle(.plain)
                    
                    
            } else {
                Text("No category selected")
            }
        }
        
    }
        
}


struct AddModelPreview : PreviewProvider {
    static var previews: some View {
        AddModelView(modelManager : ModelManager())
            .environmentObject(AppModel())
            .environmentObject(ARViewModel())
    }
    
}
