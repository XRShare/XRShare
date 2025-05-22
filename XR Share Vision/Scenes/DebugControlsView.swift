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
        NavigationStack {
            VStack(spacing: 12) {
                headerSection
                modelControlButtons
                transformSection
                Divider()
                if showModelList { modelListsSection }
                currentModelSection
                syncSection
                testMessageSection
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem {
                    Button(action: { showModelList.toggle() }) {
                        Image(systemName: showModelList ? "list.bullet.circle.fill"
                                                        : "list.bullet.circle")
                    }
                }
            }
        }
    }

    // MARK: - Sub‑sections

    @ViewBuilder
    private var headerSection: some View {
        Text("XR Anatomy Debug Controls")
            .panelHeader()
    }

    @ViewBuilder
    private var modelControlButtons: some View {
        HStack(spacing: 20) {
            Button {
                if let model = getSelectedModel() {
                    resetModel(model)
                    lastAction = "Reset model \(model.modelType.rawValue)"
                }
            } label: {
                VStack {
                    Image(systemName: "arrow.counterclockwise").font(.title3)
                    Text("Reset").font(.caption)
                }
                .frame(width: 60, height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            Button {
                if let heartType = modelManager.modelTypes.first(where: { $0.rawValue == "Heart" }) {
                    modelManager.loadModel(for: heartType, arViewModel: arViewModel)
                    lastAction = "Added Heart model"
                } else if let first = modelManager.modelTypes.first {
                    modelManager.loadModel(for: first, arViewModel: arViewModel)
                    lastAction = "Added \(first.rawValue) model"
                }
            } label: {
                VStack {
                    Image(systemName: "plus.circle").font(.title3)
                    Text("Add").font(.caption)
                }
                .frame(width: 60, height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Text("Debug Console")
                .font(.caption)
                .padding(8)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var transformSection: some View {
        VStack(spacing: 8) {
            Text("Scale").font(.subheadline)
            HStack {
                Text("0.05").font(.caption)
                Slider(
                    value: Binding(
                        get: { Double(scaleAmount) },
                        set: { newVal in
                            scaleAmount = Float(newVal)
                            if let m = getSelectedModel() { scaleTo(m, scale: scaleAmount) }
                        }),
                    in: 0.05...1.0
                )
                Text("1.0").font(.caption)
            }

            Text("Rotation").font(.subheadline).padding(.top, 4)
            HStack(spacing: 12) {
                ForEach(["X", "Y", "Z"], id: \.self) { axis in
                    Button {
                        if let m = getSelectedModel() { rotateModel(m, axis: axis) }
                    } label: {
                        Text(axis).font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(axis == "X" ? .red : (axis == "Y" ? .green : .blue))
                }
            }
        }
    }

    @ViewBuilder
    private var modelListsSection: some View {
        VStack(alignment: .leading) {
            Text("Available Models:").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(modelManager.modelTypes) { type in
                        Button {
                            modelManager.loadModel(for: type, arViewModel: arViewModel)
                            lastAction = "Added \(type.rawValue) model"
                        } label: {
                            HStack {
                                Text(type.rawValue)
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

            if !modelManager.placedModels.isEmpty {
                Text("Loaded Models:").font(.headline).padding(.top, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(modelManager.placedModels) { model in
                            Button {
                                modelManager.selectedModelID = model.modelType
                                lastAction = "Selected \(model.modelType.rawValue) model"
                            } label: {
                                HStack {
                                    Text(model.modelType.rawValue)
                                        .foregroundColor(
                                            modelManager.selectedModelID == model.modelType
                                            ? .blue : .primary
                                        )
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

    @ViewBuilder
    private var currentModelSection: some View {
        if !modelManager.placedModels.isEmpty {
            HStack {
                Text("Current Model: ").font(.subheadline)
                if let selected = getSelectedModel() {
                    Text(selected.modelType.rawValue).bold()
                } else {
                    Text("None selected").foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Image Target Sync:").font(.headline)
            imageSyncStatus
        }
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var imageSyncStatus: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle()
                    .fill(arViewModel.isImageTracked ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(
                    arViewModel.isImageTracked
                        ? "Image Target Detected"
                        : "Searching for Image Target..."
                )
                    .font(.caption)
                    .foregroundColor(arViewModel.isImageTracked ? .primary : .secondary)
            }
            if arViewModel.isSyncedToImage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Synced via Image").font(.caption)
                    Spacer()
                    Button("Re-Sync") {
                        arViewModel.triggerSync()
                        lastAction = "Triggered Image Re-Sync"
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Text("Awaiting Image Sync...")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }


    @ViewBuilder
    private var testMessageSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last Action:").font(.headline)
            Text(lastAction)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }


    func getSelectedModel() -> Model? {
        if let selectedModelID = modelManager.selectedModelID {
            return modelManager.placedModels.first(where: { $0.modelType == selectedModelID })
        } 
        return modelManager.placedModels.first
    }

    func resetModel(_ model: Model) {
        guard let entity = model.modelEntity else { return }

        let originalPosition = entity.position
        entity.scale = SIMD3<Float>(repeating: 0.15)
        entity.transform.rotation = simd_quatf(angle: 0, axis: [0, 1, 0])
        entity.position = originalPosition
        model.scale = entity.scale
        model.rotation = entity.transform.rotation

        if let arViewModel = model.arViewModel {
            arViewModel.sendTransform(for: entity)
        }

        scaleAmount = 0.15
    }

    func scaleTo(_ model: Model, scale: Float) {
        guard let entity = model.modelEntity else { return }

        let originalPosition = entity.position
        let newScale = SIMD3<Float>(repeating: scale)
        entity.scale = newScale
        entity.position = originalPosition
        model.scale = newScale

        if let arViewModel = model.arViewModel {
            arViewModel.sendTransform(for: entity)
        }
    }

    func rotateModel(_ model: Model, axis: String) {
        guard let entity = model.modelEntity else { return }

        let originalPosition = entity.position
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

        let newRotation = simd_quatf(angle: .pi / 4, axis: rotationAxis)
        entity.transform.rotation = entity.transform.rotation * newRotation
        entity.position = originalPosition
        model.rotation = entity.transform.rotation

        if let arViewModel = model.arViewModel {
            arViewModel.sendTransform(for: entity)
        }

        lastAction = "Rotated \(model.modelType.rawValue) around \(axis)-axis"
    }
}