import SwiftUI
import RealityKit

struct DebugControlsView: View {
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var arViewModel: ARViewModel
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    
    @State private var lastAction = "Debug panel opened"
    @State private var showModelList = true
    @State private var scaleAmount: Float = 0.15
    @State private var rotationX: Float = 0
    @State private var rotationY: Float = 0
    @State private var rotationZ: Float = 0
    
    var body: some View {
        return NavigationStack {
            VStack(spacing: 12) {
                Text("XR Anatomy Debug Controls")
                    .panelHeader()
                
                // Model selection and transformation controls
                HStack(spacing: 20) {
                    // Reset position button
                    Button(action: {
                        if let model = getSelectedModel() {
                            resetModel(model)
                            lastAction = "Reset model \(model.modelType.rawValue)"
                        }
                    }) {
                        VStack {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.title3)
                            Text("Reset")
                                .font(.caption)
                        }
                        .frame(width: 60, height: 50)
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
                                .font(.title3)
                            Text("Add")
                                .font(.caption)
                        }
                        .frame(width: 60, height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    
                    // No additional control panel button needed
                    Text("Debug Console")
                        .font(.caption)
                        .padding(8)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                        .foregroundColor(.secondary)
                }
                
                // Transformation controls
                VStack(spacing: 8) {
                    Text("Scale")
                        .font(.subheadline)
                    
                    HStack {
                        Text("0.05")
                            .font(.caption)
                        
                        Slider(value: Binding(
                            get: { Double(scaleAmount) },
                            set: { newValue in
                                scaleAmount = Float(newValue)
                                
                                if let model = getSelectedModel() {
                                    scaleTo(model, scale: scaleAmount)
                                }
                            }
                        ), in: 0.05...1.0)
                        
                        Text("1.0")
                            .font(.caption)
                    }
                    
                    Text("Rotation")
                        .font(.subheadline)
                        .padding(.top, 4)
                    
                    // Rotation buttons
                    HStack(spacing: 12) {
                        ForEach(["X", "Y", "Z"], id: \.self) { axis in
                            Button(action: {
                                if let model = getSelectedModel() {
                                    rotateModel(model, axis: axis)
                                }
                            }) {
                                Text(axis)
                                    .font(.headline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .tint(axis == "X" ? .red : (axis == "Y" ? .green : .blue))
                        }
                    }
                
                Divider()
                
                // Model management
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
                        
                        // Current loaded models with selection
                        if !modelManager.placedModels.isEmpty {
                            Text("Loaded Models:")
                                .font(.headline)
                                .padding(.top, 8)
                            
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(modelManager.placedModels) { model in
                                        Button(action: {
                                            modelManager.selectedModelID = model.modelType
                                            lastAction = "Selected \(model.modelType.rawValue) model"
                                        }) {
                                            HStack {
                                                Text(model.modelType.rawValue)
                                                    .foregroundColor(modelManager.selectedModelID == model.modelType ? .blue : .primary)
                                                Spacer()
                                                if modelManager.selectedModelID == model.modelType {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundColor(.blue)
                                                }
                                            }
                                            .padding(.vertical, 4)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .frame(height: 100)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
                
                // Current model section
                if !modelManager.placedModels.isEmpty {
                    HStack {
                        Text("Current Model: ")
                            .font(.subheadline)
                        
                        if let selectedModel = getSelectedModel() {
                            Text(selectedModel.modelType.rawValue)
                                .font(.subheadline.bold())
                        } else {
                            Text("None selected")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Sync Mode Selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sync Mode:")
                        .font(.headline)
                    
                    Picker("Sync Mode", selection: $arViewModel.currentSyncMode) {
                        ForEach(SyncMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: arViewModel.currentSyncMode) { _ in
                        // Post notification for sync mode change
                        NotificationCenter.default.post(name: Notification.Name("syncModeChanged"), object: nil)
                        lastAction = "Switched to \(arViewModel.currentSyncMode.rawValue)"
                    }
                    
                    // Show image tracking status when in image target mode
                    if arViewModel.currentSyncMode == .imageTarget {
                        HStack {
                            Circle()
                                .fill(appState.isImageTracked ? Color.green : Color.red)
                                .frame(width: 10, height: 10)
                            
                            Text(appState.isImageTracked ? "Image Target Detected" : "Searching for Image Target...")
                                .font(.caption)
                                .foregroundColor(appState.isImageTracked ? .primary : .secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                
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
        .withWindowOpener() // Add capability to open windows
    }
    
    // Helper functions for model manipulation
    
    // Get the currently selected model based on selectedModelID
    func getSelectedModel() -> Model? {
        // If we have a selectedModelID, find the corresponding model
        if let selectedModelID = modelManager.selectedModelID {
            return modelManager.placedModels.first(where: { $0.modelType == selectedModelID })
        } 
        // Fallback to the first model if none is explicitly selected
        return modelManager.placedModels.first
    }
    
    // Reset model to default position and orientation
    func resetModel(_ model: Model) {
        guard let entity = model.modelEntity else { return }
        
        // Save original position
        let originalPosition = entity.position
        
        // Reset scale and rotation
        entity.scale = SIMD3<Float>(repeating: 0.15)
        entity.transform.rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
        
        // Keep original position
        entity.position = originalPosition
        
        // Update model data
        model.scale = entity.scale
        model.rotation = entity.transform.rotation
        
        // Force update for multiplayer
        if let arViewModel = model.arViewModel {
            arViewModel.sendTransform(for: entity)
        }
        
        // Update slider value
        scaleAmount = 0.15
    }
    
    // Scale model while keeping its position fixed
    func scaleTo(_ model: Model, scale: Float) {
        guard let entity = model.modelEntity else { return }
        
        // Save original position
        let originalPosition = entity.position
        
        // Apply new scale uniformly
        let newScale = SIMD3<Float>(repeating: scale)
        entity.scale = newScale
        
        // Restore original position
        entity.position = originalPosition
        
        // Update model data
        model.scale = newScale
        
        // Force update for multiplayer
        if let arViewModel = model.arViewModel {
            arViewModel.sendTransform(for: entity)
        }
    }
    
    // Rotate model around specified axis while keeping position fixed
    func rotateModel(_ model: Model, axis: String) {
        guard let entity = model.modelEntity else { return }
        
        // Save original position
        let originalPosition = entity.position
        
        // Create rotation based on axis
        let rotationAxis: SIMD3<Float>
        switch axis {
        case "X":
            rotationAxis = [1, 0, 0]
            rotationX += .pi / 4
        case "Y":
            rotationAxis = [0, 1, 0]
            rotationY += .pi / 4
        case "Z":
            rotationAxis = [0, 0, 1]
            rotationZ += .pi / 4
        default:
            rotationAxis = [0, 1, 0]
        }
        
        // Apply rotation (90 degrees or π/2 radians)
        let newRotation = simd_quatf(angle: .pi / 4, axis: rotationAxis)
        entity.transform.rotation = entity.transform.rotation * newRotation
        
        // Restore original position
        entity.position = originalPosition
        
        // Update model data
        model.rotation = entity.transform.rotation
        
        // Force update for multiplayer
        if let arViewModel = model.arViewModel {
            arViewModel.sendTransform(for: entity)
        }
        
        lastAction = "Rotated \(model.modelType.rawValue) around \(axis)-axis"
    }
}
}