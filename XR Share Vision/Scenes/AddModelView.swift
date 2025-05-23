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
                    modelManager.showingModelPopover = false
                    modelManager.showingPopover.toggle()
                    
                }){
                    Image(systemName: "chevron.left")
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
            
            ScrollView {
                if let selectedCategory = appModel.selectedCategory {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        ForEach(modelManager.models(for: selectedCategory), id: \.id) { modelType in
                            Button(action: {
                                modelManager.loadModel(for: modelType, arViewModel: arViewModel)
                                modelManager.showingPopover = false
                                modelManager.showingModelPopover = false
                                dismissWindow(id: "ModelMenuBar")
                                openWindow(id: "ModelMenuBar")
                            }) {
                                VStack(spacing: 8) {
                                    
                                    Image(systemName: "cube")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(height: 100)
                                        .padding()
                                        .cornerRadius(12)

                                    Text(modelType.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.center)
                                }
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(16)
                                .shadow(radius: 4)
                            }
                        }
                    }
                    .padding()
                } else {
                    Text("No category selected")
                        .padding()
                }
            }

            
        }
        
    }
}
