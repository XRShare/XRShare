import SwiftUI
import RealityKit
import Combine
import MultipeerConnectivity

class RealityViewModel: NSObject, ObservableObject {
    @Published var selectedModel: Model? = nil
    @Published var alertItem: AlertItem?
    @Published var connectedPeers: [MCPeerID] = []
    @Published var loadingProgress: Float = 0.0

    private var subscriptions = Set<AnyCancellable>()
    private var multipeerSession: MultipeerSession?
    private var shouldStartMultipeerSession = false
    var models: [Model] = []
    var placedEntities: [UUID: Entity] = [:]
    var realityViewContent: RealityViewContent?
    private var modelCache: [String: ModelEntity] = [:]

    override init() { super.init() }

    func onAppear() {
        startMultipeerServices()
    }
    func onDisappear() {
        // Clean up if needed
    }

    // MARK: - Load Models
    func loadModel(named name: String) async throws -> ModelEntity {
        if let cached = modelCache[name] { return cached }
        let entity = try await ModelEntity(named: name)
        modelCache[name] = entity
        return entity
    }

    func loadModels() {
        guard models.isEmpty else { return }
        let modelTypes = ModelType.allCases()
        let total = modelTypes.count
        var loaded = 0

        for mt in modelTypes {
            let model = Model(modelType: mt)
            models.append(model)
            model.$loadingState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in
                    guard let self = self else { return }
                    switch state {
                    case .loaded:
                        loaded += 1
                        self.loadingProgress = Float(loaded) / Float(total)
                        if loaded == total {
                            self.enableMultipeerServicesIfDeferred()
                        }
                    case .failed(let err):
                        self.alertItem = AlertItem(title: "Failed to Load Model",
                                                   message: "\(mt.rawValue.capitalized): \(err.localizedDescription)")
                    default: break
                    }
                }
                .store(in: &subscriptions)
        }
    }

    // MARK: - Multipeer
    func startMultipeerServices() {
        guard multipeerSession == nil else { return }
        multipeerSession = MultipeerSession()
        multipeerSession?.delegate = self
        print("Multipeer services started for visionOS")
        shouldStartMultipeerSession = false
    }
    func deferMultipeerServicesUntilModelsLoad() {
        shouldStartMultipeerSession = true
    }
    func enableMultipeerServicesIfDeferred() {
        if shouldStartMultipeerSession {
            startMultipeerServices()
        }
    }

    func clearAllModels() {
        realityViewContent?.entities.removeAll()
        placedEntities.removeAll()
    }
}

extension RealityViewModel: MultipeerSessionDelegate {
    func receivedData(_ data: Data, from peerID: MCPeerID) {
        guard data.count > 1 else { return }
        let dataTypeByte = data.first!
        let rest = data.advanced(by: 1)
        if let dt = DataType(rawValue: dataTypeByte) {
            switch dt {
            case .arWorldMap:
                print("Received ARWorldMap, not fully used in visionOS sample.")
            case .anchor:
                print("Received anchor data, ignoring in visionOS sample.")
            case .collaborationData:
                print("Received collaboration data, ignoring in simple sample. Could unify ARKit here if needed.")
            case .modelTransform:
                handleModelTransform(rest)
            default:
                print("Unhandled data type in visionOS: \(dt)")
            }
        }
    }

    func handleModelTransform(_ data: Data) {
        do {
            let payload = try JSONDecoder().decode(ModelTransformPayload.self, from: data)
            Task { @MainActor in
                if let ent = findModelEntity(by: payload.modelID) {
                    let mat = simd_float4x4.fromArray(payload.transform)
                    ent.transform.matrix = mat
                } else {
                    print("Model entity not found: \(payload.modelID)")
                }
            }
        } catch {
            print("Failed to decode model transform: \(error)")
        }
    }

    func findModelEntity(by modelID: String) -> ModelEntity? {
        for e in placedEntities.values {
            if let found = e.findEntity(named: modelID) as? ModelEntity {
                return found
            }
        }
        return nil
    }

    func peerDidChangeState(peerID: MCPeerID, state: MCSessionState) {
        switch state {
        case .connected:
            if !connectedPeers.contains(peerID) {
                connectedPeers.append(peerID)
            }
        case .notConnected:
            if let i = connectedPeers.firstIndex(of: peerID) {
                connectedPeers.remove(at: i)
            }
        case .connecting:
            print("Connecting to \(peerID.displayName)")
        @unknown default:
            print("Unknown state: \(peerID.displayName)")
        }
    }

    func didReceiveInvitation(from peerID: MCPeerID,
                              invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // In this simplified version, auto-accept
        invitationHandler(true, multipeerSession?.session)
    }
}
