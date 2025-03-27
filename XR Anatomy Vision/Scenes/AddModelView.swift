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
