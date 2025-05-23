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
    
    @State private var hoveredModel: ModelType? = nil
    

    
    var body: some View {
        VStack(spacing: 0) {
            // Enhanced header with spatial design
            HStack {
                Button(action: {
                    dismissWindow(id: "AddModelWindow")
                    modelManager.showingModelPopover = false
                    modelManager.showingPopover.toggle()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.borderless)
                .hoverEffect(.highlight)
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text("Models")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    if let selectedCategory = appModel.selectedCategory {
                        Text(selectedCategory.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Category info or settings button could go here
                Color.clear.frame(width: 32, height: 32)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)
            .padding(.horizontal, 24)
            .background(.ultraThinMaterial)
            
            Spacer()
            
            // Enhanced model grid with previews
            ScrollView {
                if let selectedCategory = appModel.selectedCategory {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ],
                        spacing: 20
                    ) {
                        ForEach(modelManager.models(for: selectedCategory), id: \.id) { modelType in
                            VisionOSModelSelectionCard(
                                modelType: modelType,
                                isHovered: hoveredModel == modelType
                            ) {
                                // Load model action
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    modelManager.loadModel(for: modelType, arViewModel: arViewModel)
                                    modelManager.showingPopover = false
                                    modelManager.showingModelPopover = false
                                    dismissWindow(id: "ModelMenuBar")
                                    openWindow(id: "ModelMenuBar")
                                }
                            }
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    hoveredModel = hovering ? modelType : nil
                                }
                            }
                        }
                    }
                    .padding(24)
                } else {
                    // Enhanced empty state
                    VStack(spacing: 16) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 48, weight: .light))
                            .foregroundStyle(.tertiary)
                        
                        Text("No Category Selected")
                            .font(.title3)
                            .fontWeight(.medium)
                        
                        Text("Choose a category to browse available models")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                }
            }

            
        }
        .background(.regularMaterial)
        .glassBackgroundEffect()
    }
}

// MARK: - VisionOS Model Selection Card

struct VisionOSModelSelectionCard: View {
    let modelType: ModelType
    let isHovered: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                // Model preview section
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.thickMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(isHovered ? 0.15 : 0.08))
                        }
                    
                    // Model preview with loading state
                    UnifiedModelPreview(
                        modelType: modelType,
                        size: CGSize(width: 120, height: 120),
                        showBackground: false
                    )
                    .scaleEffect(isHovered ? 1.05 : 1.0)
                }
                .frame(height: 140)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                }
                
                // Model information
                VStack(spacing: 4) {
                    Text(modelType.rawValue)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    
                    Text(modelType.category?.localizedName ?? "Unknown")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                
                // Add button indicator
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                    
                    Text("Add Model")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.blue)
                .opacity(isHovered ? 1.0 : 0.7)
            }
            .padding(16)
        }
        .frame(width: 180, height: 240)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(isHovered ? 0.4 : 0.2), lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(0.1),
            radius: isHovered ? 12 : 6,
            x: 0,
            y: isHovered ? 6 : 3
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .buttonStyle(.borderless)
        .hoverEffect(.lift)
    }
}
