# XRShare

XRShare is a cross-platform AR/MR application for iOS and visionOS that enables collaborative viewing and manipulation of 3D anatomical models in real-time. The project demonstrates advanced AR synchronization techniques and showcases how to:

* Load and display USDZ assets with RealityKit across platforms
* Implement synchronized multi-user AR experiences using image target anchoring
* Handle real-time model transforms with Multipeer Connectivity and SharePlay
* Support cross-platform interactions between iPhone, iPad, and Apple Vision Pro
* Manage platform-specific AR features (ARKit on iOS, ARKitSession on visionOS)
* Implement sophisticated gesture handling for 3D model manipulation


## Requirements

• Xcode 15 or later  
• Swift 5.9  
• iOS 16 / iPadOS 16 or later **or** visionOS 1.0  
• A-series or M-series device that supports ARKit  
• Physical devices required for full AR functionality (iOS simulator has limited AR support)
• ARReferenceImages in "SharedAnchors" asset catalog for image target synchronization
• Wi-Fi network for multipeer collaboration features


## Getting Started

1. Clone the repository.
2. Open `XR Share.xcodeproj` in Xcode.
3. Select the target scheme:
   - **XR Share** for iOS/iPadOS devices
   - **XR Share Vision** for visionOS (Apple Vision Pro)
4. Build and run on a physical device.
5. For collaborative features, ensure devices are on the same Wi-Fi network.
6. Use the physical image targets from the "SharedAnchors" asset catalog for synchronized placement.


### Adding your own models

The application looks for USDZ files in `Shared/models`.  Copy any additional assets into this folder and rebuild.  If a model should rotate around the Z axis by default add its filename (without extension) to the `zAxisRotationModels` array in `Shared/ModelType.swift`.


## Collaboration Workflow

### Session Management
1. **Host Session**: Device advertises availability and manages session state
2. **Join Session**: Other devices discover and connect to active sessions
3. **Local Session**: Single-device mode without networking

### Image Target Synchronization
1. Point devices at the same physical image target (from SharedAnchors catalog)
2. App automatically aligns coordinate systems when image is detected
3. All subsequent model placements are relative to this shared anchor
4. Models remain synchronized even when image target is no longer visible

### Real-time Collaboration
- **Model Placement**: Any authorized user can place models in shared space
- **Transform Sync**: Drag, scale, and rotation gestures sync in real-time
- **Permission Control**: Host can grant/revoke edit permissions
- **Late Joiners**: New users receive complete scene state upon connection

### Platform-Specific Features
- **iOS**: Tap-to-place, multi-touch gestures, world map sharing
- **visionOS**: 3D spatial gestures, immersive space, window-based controls
- **Cross-Platform**: Full interoperability between iOS and visionOS devices


## Architecture Overview

### Core Components

**Shared/** - Platform-independent business logic and networking
- `ARViewModel.swift` - Main AR/networking coordinator
- `ModelManager.swift` - 3D model lifecycle and gesture handling
- `MultipeerSession.swift` - Peer-to-peer networking via Multipeer Connectivity
- `MyCustomConnectivityService.swift` - Real-time synchronization service
- `Model.swift` - Individual 3D model representation and loading
- `ModelType.swift` - Model discovery and categorization
- `ModelSyncPayloads.swift` - Network message structures

**XR Share/** - iOS-specific implementation
- `ARViewContainer.swift` - ARKit integration with RealityKit
- `ARSessionManager.swift` - iOS AR session configuration
- `StartupMenuView.swift` - Host/join session interface

**XR Share Vision/** - visionOS-specific implementation  
- `XRShareVision.swift` - App entry point with window management
- `InSession.swift` - Immersive space with 3D gesture handling
- `MainMenu.swift` - Session selection interface
- Various UI windows for model selection and controls

### Synchronization System

The app uses **image target synchronization** as the primary collaboration method:
1. All devices detect the same physical image target
2. This creates a shared coordinate system for model placement
3. Model transforms are synchronized relative to this shared anchor
4. Real-time updates maintain consistency across all connected devices

### Networking Architecture

- **Local Discovery**: Multipeer Connectivity for same-network device discovery
- **Real-time Sync**: Custom payloads for model add/remove/transform operations
- **Session Roles**: Host (creates session) and Viewer (joins session) roles
- **Permission System**: Hosts can grant edit permissions to viewers
- **Conflict Resolution**: Instance-based entity tracking prevents duplicate models


## License

Provided for educational use without warranty.
