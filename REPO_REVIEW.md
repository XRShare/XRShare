## Action Items
[CS001] Code Style — Refactor all force unwraps (!) and force casts (as!) to safe optional binding across codebase | Rationale: improves safety by avoiding runtime crashes | Priority: 2 | Depends: – | Done when: no unintended forced unwraps/casts remain

[CS003] Code Style — Rename triggerImageSync() in ARViewModel to reflect its dual purpose or split into separate methods | Rationale: method name is misleading (Shared/ARViewModel.swift) | Priority: 3 | Depends: – | Done when: method(s) renamed and call sites updated

[CS004] Code Style — Add DocC comments to critical classes and methods (ARViewModel, ModelManager, MyCustomConnectivityService, sync logic) | Rationale: improves maintainability and aids onboarding | Priority: 2 | Depends: – | Done when: public APIs and complex workflows documented

[UX001] UI/UX — Provide clear user feedback for connection failures and sync errors via alerts or inline status indicators | Rationale: improves usability when multipeer connectivity issues occur | Priority: 2 | Depends: – | Done when: UI surfaces connection/sync errors to users

[UX002] UI/UX — Smooth transitions between menu and AR session on iOS and visionOS | Rationale: prevents jarring context switches | Priority: 3 | Depends: – | Done when: transitions animated and state persists correctly

[UX003] UI/UX — Standardize window management in visionOS using openWindow/dismissWindow instead of custom modifiers | Rationale: leverages SwiftUI APIs and reduces custom code complexity | Priority: 2 | Depends: – | Done when: windows opened/closed via SwiftUI environment actions

[UX004] UI/UX — Clarify or generalize the “Info Mode” feature beyond specific models to ensure consistent user understanding | Rationale: unclear purpose confuses users (XR Anatomy Vision/Scenes/ModelSelectionScreen.swift) | Priority: 3 | Depends: – | Done when: info mode behavior is intuitive or documented

[F02] New Feature — Add visual ownership indicators on models to show which peer placed them | Rationale: enhances collaboration awareness in multi-user sessions | Priority: 3 | Depends: – | 
