# XR Anatomy

XR Anatomy is a demonstration app for iOS and visionOS that lets you place, inspect and share detailed 3-D anatomical models in augmented or mixed reality.  The project shows how to:

* load and display USDZ assets with RealityKit
* apply basic gestures for translation, rotation and scaling
* synchronise model transforms between devices with Multipeer Connectivity and SharePlay
* run the same codebase on iPhone, iPad and Apple Vision Pro


## Requirements

• Xcode 15 or later  
• Swift 5.9  
• iOS 16 / iPadOS 16 or later **or** visionOS 1.0  
• A-series or M-series device that supports ARKit.  The iOS simulator is **not** sufficient for full AR functionality.


## Getting started

1. Clone the repository.
2. Open `XR Anatomy.xcodeproj` in Xcode.
3. Select the **XR Anatomy** (iOS) or **XR Anatomy Vision** (visionOS) scheme.
4. Build and run on a physical device.


### Adding your own models

The application looks for USDZ files in `Shared/models`.  Copy any additional assets into this folder and rebuild.  If a model should rotate around the Z axis by default add its filename (without extension) to the `zAxisRotationModels` array in `Shared/ModelType.swift`.


## Collaboration workflow

At launch you can host a new session or join an existing one on the same Wi-Fi network:

* **Host session** – starts advertising with Multipeer Connectivity and SharePlay.
* **Join session** – discovers hosts and synchronises the scene state (placed models and their transforms).

The host can optionally grant edit permission to connected viewers.


## File overview

• **Shared/**   Platform-independent logic, data models and networking code.  
• **XR Anatomy/**   iOS-specific UI and ARKit integration.  
• **XR Anatomy Vision/**   visionOS scene, windows and services.  
• **Packages/RealityKitContent/**   Xcode package that bundles example Reality Composer Pro content.


## License

Provided for educational use without warranty.
