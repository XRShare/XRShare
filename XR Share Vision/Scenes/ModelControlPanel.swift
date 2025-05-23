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
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow
    
    @State private var lastAction = "Debug panel opened"
    @State private var showModelList = true
    @State private var scaleAmount: Float = 0.15
    @State private var rotationX: Float = 0
    @State private var rotationY: Float = 0
    @State private var rotationZ: Float = 0
    @State private var isModelPartSelectionOn = false
    @State private var isSlicedViewOn = false
    @State private var isOn = false
    
    var body: some View {
        
        NavigationStack {
            VStack(spacing: 12) {
                headerSection
                Divider()
                
                Text("Position")
                    .font(.headline)
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
                
                positionSection
                    
                
                
                Text("Gestures")
                    .font(.headline)
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
                
                transformSection
                   
                
                Text("Interactions")
                    .font(.headline)
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
                
                modelViews

                
                Divider()
                modelControlButtons
            }
            .padding()
        }
        
        
    }
    
    @ViewBuilder
    private var positionSection: some View{
        if let model = getSelectedModel(), let entity = model.modelEntity{
            
                HStack {
                    Text("X: \(String(format: "%.2f", entity.position.x))")
                        .font(.subheadline)
                        .frame(width: 60, alignment: .leading)
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
                .padding(.leading, 8)
                .padding(.bottom, 5)
                
                HStack {
                    Text("Y: \(String(format: "%.2f", entity.position.y))")
                        .font(.subheadline)
                        .frame(width: 60, alignment: .leading)
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
                .padding(.leading, 8)
                .padding(.bottom, 5)
                
                HStack {
                    Text("Z: \(String(format: "%.2f", entity.position.z))")
                        .font(.subheadline)
                        .frame(width: 60, alignment: .leading)
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
                .padding(.leading, 8)
            }
            
        }
    
    @ViewBuilder
    private var headerSection: some View {
        if !modelManager.placedModels.isEmpty {
            HStack {
                
                Button(action:{
                    dismissWindow(id: "ModelControlPanel")
                }){
                    Image(systemName: "xmark")
                }
                
                Spacer()
                
                Text("Current Model:")
                    .font(.headline)
                    .fontWeight(.bold)
                if let selected = getSelectedModel() {
                    Text(selected.modelType.rawValue).font(.headline).fontWeight(.bold)
                } else {
                    Text("None selected").foregroundColor(.secondary)
                }
                
                Spacer()
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
                    Text("Reset").font(.subheadline)
                }
                .frame(width: 100, height: 50)
            }
            .buttonStyle(.plain)

        }
    }
    
    
    @ViewBuilder
    private var transformSection: some View {
        VStack(spacing: 20) {

            HStack {
                Text("Scale")
                    .font(.subheadline)
                    .frame(width: 60, alignment: .leading)
                
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
            .padding(.leading, 8)
            .padding(.bottom)

        
            HStack(spacing: 12) {
                Text("Rotate")
                    .font(.subheadline)
                    .frame(width: 60, alignment: .leading)
                
                ForEach(["X", "Y", "Z"], id: \.self) { axis in
                    Button {
                        if let m = getSelectedModel() { rotateModel(m, axis: axis) }
                    } label: {
                        Text(axis).font(.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 15)
            }
            .padding(.leading, 8)
        }
        .padding(.bottom)
    }
    
    @ViewBuilder
    private var modelViews: some View {
        
        VStack(spacing: 20){
            Button(action: {
                isModelPartSelectionOn.toggle()
            }){
                HStack{
                    Text("Model-Part Selection")
                        .font(.subheadline)
                        .foregroundStyle(Color.white)
                    Spacer()
                    
                    Image(systemName: isModelPartSelectionOn ? "checkmark.circle.fill" : "circle")
                        .padding(.horizontal, 4)
                    
                    
                }
                .padding(.top)
                .padding(.bottom)
                .padding(.leading, 8)
                .background(
                    
                    Group{
                        
                        if isModelPartSelectionOn {
                            RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
                        }
                        
                        else {
                            RoundedRectangle(cornerRadius: 12).fill(Color.clear)
                        }
                            
                        })
                
            }
            .buttonStyle(.plain)
            
            Divider()
            
            
            Button(action: {
                isSlicedViewOn.toggle()
            }){
                HStack{
                    Text("Sliced Model")
                        .font(.subheadline)
                        .foregroundStyle(Color.white)
                    
                    Spacer()
                    
                    Image(systemName: isSlicedViewOn ? "checkmark.circle.fill" : "circle")
                        .padding(.horizontal, 4)
                    
                    
                }
                .padding(.top)
                .padding(.bottom)
                .padding(.leading, 8)
                .background(
                    
                    Group{
                        
                        if isSlicedViewOn {
                            RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
                        }
                        
                        else {
                            RoundedRectangle(cornerRadius: 12).fill(Color.clear)
                        }
                            
                        })
                        
                    }
                
            .buttonStyle(.plain)
            
            
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



