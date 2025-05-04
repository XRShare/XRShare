//  SharePlaySyncController.swift
//  XR Anatomy
//
//  Implements SharePlay syncing via GroupActivities without altering existing connectivity code.

import Foundation
import GroupActivities
import CoreTransferable  // Added for SharePlay UI integration

/// Defines the SharePlay activity for AR session sharing.
/// Conforms to ActivityAttributes, GroupActivity, Transferable & Sendable.
struct ARSessionActivity: GroupActivity, Transferable, Sendable {
    /// Configuration metadata for the activity.
    var metadata: GroupActivityMetadata = {
        var meta = GroupActivityMetadata()
        meta.title = "XR Anatomy"
        meta.type = .generic
        return meta
    }()
}

/// Manages a SharePlay GroupSession and broadcasts/receives AR payloads.
final class SharePlaySyncController {
    static let shared = SharePlaySyncController()
    private init() {}

    private(set) var groupSession: GroupSession<ARSessionActivity>?
    private(set) var messenger: GroupSessionMessenger?

    /// Starts the SharePlay session, sends the origin anchor, and subscribes to incoming messages.
    func startSession(with originTransform: [Float]) {
        Task {
            let activity = ARSessionActivity()
            do {
                // Request to start SharePlay activity
                let didStart = try await activity.activate()
                guard didStart else {
                    print("SharePlaySyncController: user declined or no session created")
                    return
                }

                // Listen for the first available group session
                for await session in ARSessionActivity.sessions() {
                    self.groupSession = session

                    // Initialize and store the messenger
                    let messenger = GroupSessionMessenger(session: session)
                    self.messenger = messenger

                    // Subscribe to incoming SharePlay messages
                    subscribe(to: AddModelPayload.self) { payload in
                        self.broadcastNotification(name: .sharePlayAddModel, object: payload)
                    }
                    subscribe(to: RemoveModelPayload.self) { payload in
                        self.broadcastNotification(name: .sharePlayRemoveModel, object: payload)
                    }
                    subscribe(to: ModelTransformPayload.self) { payload in
                        self.broadcastNotification(name: .sharePlayModelTransform, object: payload)
                    }
                    subscribe(to: AnchorTransformPayload.self) { payload in
                        self.broadcastNotification(name: .sharePlayAnchorTransform, object: payload)
                    }

                    // Broadcast the initial origin transform via Notification
                    self.broadcastNotification(name: .sharePlayOriginTransform, object: originTransform)

                    break
                }

            } catch {
                print("SharePlaySyncController failed to start: \\(error)")
            }
        }
    }

    /// Generic subscribe helper for Codable message types.
    /// Subscribes to incoming group session messages of a specific type.
    private func subscribe<T: Codable>(to type: T.Type, handler: @escaping (T) -> Void) {
        guard let messenger = messenger else { return }
        Task {
            for await (message, _) in messenger.messages(of: T.self) {
                handler(message)
            }
        }
    }

    /// Posts a Notification for other services to pick up.
    private func broadcastNotification(name: Notification.Name, object: Any) {
        NotificationCenter.default.post(name: name, object: object)
    }
}

// MARK: - Notification Names for SharePlay payloads
extension Notification.Name {
    static let sharePlayAddModel        = Notification.Name("shareplay.addModel")
    static let sharePlayRemoveModel     = Notification.Name("shareplay.removeModel")
    static let sharePlayModelTransform  = Notification.Name("shareplay.modelTransform")
    static let sharePlayAnchorTransform = Notification.Name("shareplay.anchorTransform")
    /// Notification for SharePlay initial origin transform content state
    static let sharePlayOriginTransform = Notification.Name("shareplay.originTransform")
}