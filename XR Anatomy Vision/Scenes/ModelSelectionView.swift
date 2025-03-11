//
//  ModelSelectionView.swift
//  XR Anatomy
//
//  Created by XR Anatomy on 2025-03-11.
//


import SwiftUI
import RealityKit

struct ModelSelectionView: View {
    @ObservedObject var modelManager: ModelManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Select a Model")
                    .font(.headline)
                    .foregroundColor(.white)
                if modelManager.modelTypes.isEmpty {
                    Text("No models found.")
                        .foregroundColor(.gray)
                } else {
                    ForEach(modelManager.modelTypes, id: \.id) { modelType in
                        Button(action: {
                            modelManager.loadModel(for: modelType,
                                                   headAnchor: AnchorEntity(.head),
                                                   arViewModel: nil)
                        }) {
                            Text("\(modelType.rawValue) Model")
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color.black.opacity(0.8))
        .cornerRadius(12)
        .padding()
    }
}

struct ModelSelectionView_Previews: PreviewProvider {
    static var previews: some View {
        // Use a sample ModelManager for preview purposes.
        ModelSelectionView(modelManager: ModelManager())
            .previewLayout(.sizeThatFits)
            .padding()
    }
}
