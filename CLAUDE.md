# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

XRShare is a cross-platform AR/VR collaboration app for iOS and visionOS that enables multiple users to view and interact with 3D models in shared spatial environments. The app uses MultipeerConnectivity and SharePlay for device-to-device synchronization.

## Build Commands

```bash
# List available schemes and targets
xcodebuild -list -project "XR Share.xcodeproj"

# Build for iOS
xcodebuild -project "XR Share.xcodeproj" -scheme "XR Share" -sdk iphoneos -configuration Debug

# Build for visionOS
xcodebuild -project "XR Share.xcodeproj" -scheme "XR Share Vision" -sdk xros -configuration Debug

# Build and run on iOS Simulator
xcodebuild -project "XR Share.xcodeproj" -scheme "XR Share" -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15'

# Clean build folder
xcodebuild -project "XR Share.xcodeproj" -scheme "XR Share" clean
```

## Architecture

The codebase follows a shared architecture pattern with platform-specific UI:

- **Shared/**: Core business logic, models, and networking code used by both platforms
- **XR Share/**: iOS-specific UI and ARKit integration
- **XR Share Vision/**: visionOS-specific scenes and window management

### Key Architectural Components

1. **Model Management**
   - `ModelManager`: Central class for 3D model loading, placement, and gesture handling
   - `ModelType`: Enum defining available USDZ models (located in Shared/models/)
   - Transform synchronization via `ModelTransformPayload`

2. **Networking Stack**
   - `MultipeerSession`: Handles peer-to-peer connectivity
   - `SharePlaySyncController`: Manages SharePlay group activities
   - `MyCustomConnectivityService`: Protocol for abstracting networking backends

3. **AR/VR State Management**
   - `ARViewModel`: Main view model coordinating all AR/XR functionality
   - `AppModel`: Global app state and settings
   - `ARSessionManager` (iOS): ARKit session lifecycle

4. **Sync Modes**
   - World Space: Direct coordinate synchronization
   - Image Target: Anchor to detected images (SharedAnchors.arresourcegroup)
   - Object Target: Anchor to scanned objects

### State Flow

```
StartupMenuView/MainMenu → Session Creation/Join → AR/VR Space → Model Placement → Transform Sync
         ↓                          ↓                      ↓              ↓
    AppModel.state          MultipeerSession      ARViewModel    ModelManager
                              SharePlaySync
```

## Key Development Tasks

### Adding New 3D Models
1. Add USDZ file to `Shared/models/`
2. Update `ModelType.categoryMap` in `Shared/ModelType.swift`
3. If model requires Z-axis rotation, add to `zAxisRotationModels` set
4. Rebuild project to include in resource bundle

### Working with Sync Features
- Host permissions managed via `hostID` in `ARViewModel`
- Transform updates broadcast via `syncModelTransform()`
- Viewer edits require `canViewerEdit` permission

### Platform-Specific Considerations
- **iOS**: Uses ARKit for world tracking and plane detection
- **visionOS**: Uses RealityKit spaces and volumetric windows
- Shared models must work in both coordinate systems

## Testing Collaboration Features

Multi-device testing requires:
1. Two or more physical devices (iOS devices or Vision Pro)
2. Same WiFi network for MultipeerConnectivity
3. For SharePlay: Active FaceTime call between devices

## Current Development Focus

Per TIMELINE.md, current priorities include:
- QR-code based sync implementation
- CloudKit integration for model catalog
- Performance optimization for large models
- App Store submission preparation (target: August 2025)