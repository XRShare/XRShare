## Action Items
[L04] Logic Bug — Prevent race conditions during model removal by broadcasting removal after local state update or using ordered sequence numbers | Rationale: transform updates arriving during removal cause errors (Shared/ModelManager.swift) | Priority: 2 | Depends: – | Done when: removal broadcasts never conflict with transform updates

[L05] Logic Bug — Correct visionOS drag gesture delta calculations to apply smooth world‑space movement in InSession | Rationale: current implementation yields jerky/unpredictable drags (XR Anatomy Vision/Scenes/InSession.swift) | Priority: 2 | Depends: – | Done when: user drag gestures result in smooth, accurate model movement

[L07] Logic Bug — Consolidate tracking flags (isImageTracked, isObjectTracked) into ARViewModel and remove duplication in AppState/AppModel | Rationale: dual sources of truth cause inconsistent UI and sync behavior | Priority: 2 | Depends: – | Done when: single source of truth in ARViewModel drives all UI/state updates

[L08] Logic Bug — Harden ARSessionDelegateHandler to reliably handle image/object anchor detection, loss, and re‑sync transitions | Rationale: complex state logic can fail on target disappearance or reacquisition (Shared/ARSessionDelegateHandler.swift) | Priority: 2 | Depends: – | Done when: iOS app correctly maintains sync state through anchor lifecycle

[P01] Performance — Optimize RealityView update loop in visionOS by minimizing per‑frame parenting and state checks | Rationale: frequent scene graph operations can degrade frame rates (XR Anatomy Vision/Scenes/InSession.swift) | Priority: 2 | Depends: L03 | Done when: update loop work reduced and performance metrics improved

[P02] Performance — Review and optimize SceneEvents.Update subscription in SessionConnectivity; batch or throttle transform messages if needed | Rationale: per-frame subscriptions may be expensive (XR Anatomy Vision/Services/SessionConnectivity.swift) | Priority: 3 | Depends: – | Done when: transform broadcasts occur efficiently with acceptable resource usage

[CS001] Code Style — Refactor all force unwraps (!) and force casts (as!) to safe optional binding across codebase | Rationale: improves safety by avoiding runtime crashes | Priority: 2 | Depends: – | Done when: no unintended forced unwraps/casts remain

[CS003] Code Style — Rename triggerImageSync() in ARViewModel to reflect its dual purpose or split into separate methods | Rationale: method name is misleading (Shared/ARViewModel.swift) | Priority: 3 | Depends: – | Done when: method(s) renamed and call sites updated

[CS004] Code Style — Add DocC comments to critical classes and methods (ARViewModel, ModelManager, MyCustomConnectivityService, sync logic) | Rationale: improves maintainability and aids onboarding | Priority: 2 | Depends: – | Done when: public APIs and complex workflows documented

[UX001] UI/UX — Provide clear user feedback for connection failures and sync errors via alerts or inline status indicators | Rationale: improves usability when multipeer connectivity issues occur | Priority: 2 | Depends: – | Done when: UI surfaces connection/sync errors to users

[UX002] UI/UX — Smooth transitions between menu and AR session on iOS and visionOS | Rationale: prevents jarring context switches | Priority: 3 | Depends: – | Done when: transitions animated and state persists correctly

[UX003] UI/UX — Standardize window management in visionOS using openWindow/dismissWindow instead of custom modifiers | Rationale: leverages SwiftUI APIs and reduces custom code complexity | Priority: 2 | Depends: – | Done when: windows opened/closed via SwiftUI environment actions

[UX004] UI/UX — Clarify or generalize the “Info Mode” feature beyond specific models to ensure consistent user understanding | Rationale: unclear purpose confuses users (XR Anatomy Vision/Scenes/ModelSelectionScreen.swift) | Priority: 3 | Depends: – | Done when: info mode behavior is intuitive or documented

[NF001] New Feature — Implement ARWorldMap sharing in Shared/ARSessionManager.swift for session join workflows | Rationale: late‑joining devices lack a shared world map, causing misaligned AR spaces contrary to product goal #2 | Priority: 1 | Depends: L01, L02 | Done when: ARSessionManager serializes current ARWorldMap, sends it to new peers, and peers restore their ARSession with the received map

[NF002] New Feature — Finalize SessionConnectivity.broadcastAnchorCreation to send anchors to remote peers and apply them correctly | Rationale: synchronizes anchor creation across devices | Priority: 2 | Depends: NF001 | Done when: anchors appear at correct positions for remote peers

[PM001] Performance — Optimize USDZ model assets in Shared/models by reducing mesh complexity and compressing textures | Rationale: improves load times and reduces memory footprint | Priority: 3 | Depends: – | Done when: models meet performance budget or guidelines

[F02] New Feature — Add visual ownership indicators on models to show which peer placed them | Rationale: enhances collaboration awareness in multi-user sessions | Priority: 3 | Depends: – | 
