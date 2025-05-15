//
//  ConnectionStatusView.swift
//  XR Anatomy
//
//  Created by Ali Kara on 2025-02-12.
//


import SwiftUI

struct ConnectionStatusView: View {
    @EnvironmentObject var arViewModel: ARViewModel

    var body: some View {
        VStack {
            if arViewModel.connectedPeers.isEmpty {
                Text("Searching for peers...")
                    .padding(8)
                    .background(Color.yellow.opacity(0.8))
                    .cornerRadius(8)
            } else {
                Text("Connected to \(arViewModel.connectedPeers.count) peer(s)")
                    .padding(8)
                    .background(Color.green.opacity(0.8))
                    .cornerRadius(8)
            }
        }
        .padding()
    }
}