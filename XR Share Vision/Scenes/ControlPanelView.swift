import SwiftUI
import RealityKit

struct ControlPanelView: View {
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var arViewModel: ARViewModel
    @EnvironmentObject var appModel: AppModel
    
    @State private var lastAction = "Control panel initialized"
    @State private var selectedModel: Model?
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Loaded Models")) {
                    if modelManager.placedModels.isEmpty {
                        Text("No models loaded yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(modelManager.placedModels) { model in
                            Button(action: {
                                selectedModel = model
                            }) {
                                HStack {
                                    Text(model.modelType.rawValue)
                                        .fontWeight(selectedModel?.id == model.id ? .bold : .regular)
                                    Spacer()
                                    Image(systemName: "checkmark")
                                        .opacity(selectedModel?.id == model.id ? 1.0 : 0.0)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    Divider()
                    
                    Menu("Add Model") {
                        ForEach(modelManager.modelTypes) { modelType in
                            Button(action: {
                                modelManager.loadModel(for: modelType, arViewModel: arViewModel)
                                lastAction = "Added \(modelType.rawValue) model"
                            }) {
                                Text(modelType.rawValue)
                            }
                        }
                    }
                }
                
                if let model = selectedModel, let entity = model.modelEntity {
                    Section(header: Text("Position: \(model.modelType.rawValue)")) {
                        HStack {
                            Text("X: \(String(format: "%.2f", entity.position.x))")
                            Spacer()
                            Button("-0.05") {
                                entity.position.x -= 0.05
                                model.position = entity.position
                                // Force model update
                                if let arViewModel = model.arViewModel {
                                    arViewModel.sendTransform(for: entity)
                                }
                                lastAction = "Moved \(model.modelType.rawValue) left"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            
                            Button("+0.05") {
                                entity.position.x += 0.05
                                model.position = entity.position
                                // Force model update
                                if let arViewModel = model.arViewModel {
                                    arViewModel.sendTransform(for: entity)
                                }
                                lastAction = "Moved \(model.modelType.rawValue) right"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        
                        HStack {
                            Text("Y: \(String(format: "%.2f", entity.position.y))")
                            Spacer()
                            Button("-0.05") {
                                entity.position.y -= 0.05
                                model.position = entity.position
                                // Force model update
                                if let arViewModel = model.arViewModel {
                                    arViewModel.sendTransform(for: entity)
                                }
                                lastAction = "Moved \(model.modelType.rawValue) down"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            
                            Button("+0.05") {
                                entity.position.y += 0.05
                                model.position = entity.position
                                // Force model update
                                if let arViewModel = model.arViewModel {
                                    arViewModel.sendTransform(for: entity)
                                }
                                lastAction = "Moved \(model.modelType.rawValue) up"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        
                        HStack {
                            Text("Z: \(String(format: "%.2f", entity.position.z))")
                            Spacer()
                            Button("-0.05") {
                                entity.position.z -= 0.05
                                model.position = entity.position
                                // Force model update
                                if let arViewModel = model.arViewModel {
                                    arViewModel.sendTransform(for: entity)
                                }
                                lastAction = "Moved \(model.modelType.rawValue) closer"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            
                            Button("+0.05") {
                                entity.position.z += 0.05
                                model.position = entity.position
                                // Force model update
                                if let arViewModel = model.arViewModel {
                                    arViewModel.sendTransform(for: entity)
                                }
                                lastAction = "Moved \(model.modelType.rawValue) away"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                    
                    Section(header: Text("Scale & Rotation")) {
                        HStack {
                            Text("Scale: \(String(format: "%.2f", entity.scale.x))")
                            Spacer()
                            Button("÷2") {
                                entity.scale *= 0.5
                                model.scale = entity.scale
                                // Force model update
                                if let arViewModel = model.arViewModel {
                                    arViewModel.sendTransform(for: entity)
                                }
                                lastAction = "Halved \(model.modelType.rawValue) scale"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            
                            Button("×2") {
                                entity.scale *= 2.0
                                model.scale = entity.scale
                                // Force model update
                                if let arViewModel = model.arViewModel {
                                    arViewModel.sendTransform(for: entity)
                                }
                                lastAction = "Doubled \(model.modelType.rawValue) scale"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        
                        HStack {
                            Text("Rotation")
                            Spacer()
                            Button("X") {
                                let rotation = simd_quatf(angle: .pi/2, axis: [1, 0, 0])
                                entity.transform.rotation = rotation
                                model.rotation = rotation
                                // Force model update
                                if let arViewModel = model.arViewModel {
                                    arViewModel.sendTransform(for: entity)
                                }
                                lastAction = "Rotated \(model.modelType.rawValue) X"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            
                            Button("Y") {
                                let rotation = simd_quatf(angle: .pi/2, axis: [0, 1, 0])
                                entity.transform.rotation = rotation
                                model.rotation = rotation
                                // Force model update
                                if let arViewModel = model.arViewModel {
                                    arViewModel.sendTransform(for: entity)
                                }
                                lastAction = "Rotated \(model.modelType.rawValue) Y"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            
                            Button("Z") {
                                let rotation = simd_quatf(angle: .pi/2, axis: [0, 0, 1])
                                entity.transform.rotation = rotation
                                model.rotation = rotation
                                // Force model update
                                if let arViewModel = model.arViewModel {
                                    arViewModel.sendTransform(for: entity)
                                }
                                lastAction = "Rotated \(model.modelType.rawValue) Z"
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        
                        Button("Reset Transform") {
                            entity.position = [0, 0, -0.5]
                            entity.scale = [0.15, 0.15, 0.15]
                            entity.transform.rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
                            model.position = entity.position
                            model.scale = entity.scale
                            model.rotation = entity.transform.rotation
                            
                            // Force model update
                            if let arViewModel = model.arViewModel {
                                arViewModel.sendTransform(for: entity)
                            }
                            lastAction = "Reset \(model.modelType.rawValue) transform"
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Remove Model") {
                            let modelName = model.modelType.rawValue
                            modelManager.removeModel(model)
                            selectedModel = nil
                            lastAction = "Removed \(modelName)"
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                } else {
                    Section {
                        Text("Select a model to modify")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Scene Controls")) {
                    Button("Reset All Models") {
                        modelManager.reset()
                        selectedModel = nil
                        lastAction = "Reset all models"
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                
                Section(header: Text("Status")) {
                    Text(lastAction)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Model Controls")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            // Select first model if available
            if let firstModel = modelManager.placedModels.first {
                selectedModel = firstModel
            }
        }
    }
}