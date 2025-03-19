import SwiftUI
import RealityKit

struct DebugControlsView: View {
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var arViewModel: ARViewModel
    @EnvironmentObject var appModel: AppModel
    
    @State private var lastAction = "Debug panel opened"
    @State private var showModelList = true
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("XR Anatomy Debug Controls")
                    .font(.headline)
                    .padding(.top, 8)
                
                // Model manipulation buttons
                HStack(spacing: 20) {
                    // Reset position button
                    Button(action: {
                        if let firstModel = modelManager.placedModels.first,
                           let entity = firstModel.modelEntity {
                            entity.position = SIMD3<Float>(0, 0, -0.5)
                            firstModel.position = entity.position
                            
                            // Force update for multiplayer
                            if let arViewModel = firstModel.arViewModel {
                                arViewModel.sendTransform(for: entity)
                            }
                            lastAction = "Reset position for \(firstModel.modelType.rawValue)"
                        }
                    }) {
                        VStack {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.title2)
                            Text("Reset")
                                .font(.caption)
                        }
                        .frame(width: 70, height: 60)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    
                    // Add model button
                    Button(action: {
                        if let heartType = modelManager.modelTypes.first(where: { $0.rawValue == "Heart" }) {
                            modelManager.loadModel(for: heartType, arViewModel: arViewModel)
                            lastAction = "Added Heart model"
                        } else if let firstModel = modelManager.modelTypes.first {
                            modelManager.loadModel(for: firstModel, arViewModel: arViewModel)
                            lastAction = "Added \(firstModel.rawValue) model"
                        }
                    }) {
                        VStack {
                            Image(systemName: "plus.circle")
                                .font(.title2)
                            Text("Add")
                                .font(.caption)
                        }
                        .frame(width: 70, height: 60)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    
                    // Control panel button
                    Button(action: {
                        Task { @MainActor in
                            async let _ = openWindow(id: "controlPanel")
                        }
                        lastAction = "Opened control panel"
                    }) {
                        VStack {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title2)
                            Text("Controls")
                                .font(.caption)
                        }
                        .frame(width: 70, height: 60)
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Divider()
                
                // Model selection
                if showModelList {
                    VStack(alignment: .leading) {
                        Text("Available Models:")
                            .font(.headline)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(modelManager.modelTypes) { modelType in
                                    Button(action: {
                                        modelManager.loadModel(for: modelType, arViewModel: arViewModel)
                                        lastAction = "Added \(modelType.rawValue) model"
                                    }) {
                                        HStack {
                                            Text(modelType.rawValue)
                                            Spacer()
                                            Image(systemName: "plus")
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 120)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                Text("Status: \(lastAction)")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem {
                    Button(action: {
                        showModelList.toggle()
                    }) {
                        Image(systemName: showModelList ? "list.bullet.circle.fill" : "list.bullet.circle")
                    }
                }
            }
        }
        .onAppear {
            // Automatically open the control panel when the debug panel is opened
            Task {
                async let _ = openWindow(id: "controlPanel")
            }
        }
    }
}