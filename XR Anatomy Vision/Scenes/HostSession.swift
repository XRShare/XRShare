//
//  HostSesion.swift
//  XR Anatomy
//
//  Created by Marko Vujic on 2024-12-11.
//


import SwiftUI

struct HostSession: View {
    @EnvironmentObject var appModel: AppModel
    
    var body: some View {
        VStack {
            Text("Hosting Session").font(.title)
            // Show some session info; for instance, your peer ID could be the session ID.
            if let session = appModel.multipeerSession {
                Text("Your Session: \(session.myPeerID.displayName)")
            } else {
                Text("Starting session...")
            }
            Button("Start Session") {
                // As the host, after setting up, transition to the in-session view.
                appModel.currentPage = .inSession
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
            Button("Back") {
                appModel.currentPage = .mainMenu
            }
            .padding()
        }
    }
}
