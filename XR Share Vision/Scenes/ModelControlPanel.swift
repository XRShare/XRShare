//
//  ModelControlPanel.swift
//  XR Share Vision
//
//  Created by Joanna  Lin  on 2025-05-22.
//

import Foundation

import SwiftUI
import RealityKit

struct ModelControlPanelView: View {
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
                Divider()
                transformSection
                
                Spacer()
                
                modelControlButtons
            }
            .padding()
        }
        
        
    }
    
    @ViewBuilder
    private var headerSection: some View {
        if !modelManager.placedModels.isEmpty {
            HStack {
                Text("Current Model: ").font(.subheadline)
                if let selected = getSelectedModel() {
                    Text(selected.modelType.rawValue).bold()
                } else {
                    Text("None selected").foregroundColor(.secondary)
                }
            }
            .padding()
        }
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
                HStack {
                    Image(systemName: "arrow.counterclockwise").font(.title3)
                    Text("Reset").font(.caption)
                }
                .frame(width: 60, height: 50)
            }
            .buttonStyle(.plain)

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



