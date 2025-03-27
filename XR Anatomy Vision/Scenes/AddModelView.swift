//
//  SwiftUIView.swift
//  XR Anatomy Vision
//
//  Created by Joanna  Lin  on 2025-03-23.
//

import SwiftUI
import RealityKit
import RealityKitContent

struct AddModelView: View {
    @Environment(\.openWindow) private var openWindow
    
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var arViewModel: ARViewModel
    @ObservedObject var modelManager: ModelManager

    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        VStack{
            
            Text("Models")
                .font(.title)
                .padding(30)
            
            Spacer()
            
            List(modelManager.modelTypes, id: \.id){ modelType in
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
