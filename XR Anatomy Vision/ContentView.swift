//
//  ContentView.swift
//  XRAnatomy-visionOS
//
//  Created by Marko Vujic on 2024-12-10.
//

import SwiftUI
import RealityKit
import RealityKitContent



struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    
    var body: some View {
        
        switch appModel.currentPage {
        case .home:
            MainMenu()
        case .joinSession:
            JoinSession()
        case .hostSession:
            HostSession()
        case .inSession:
            InSession()
        }
        
    }
}
#Preview(windowStyle: .volumetric) {
    ContentView()
        .environment(AppModel())
}
