# XR Anatomy App

An augmented reality anatomy application for iOS and visionOS that allows users to view, manipulate and collaborate with 3D anatomical models.

## 🧩 Features

- View detailed 3D anatomical models in AR
- Collaborate with other users in real-time
- Place models in your physical space
- Manipulate models with gestures (rotation, scale, translation)
- Cross-platform support for iOS and visionOS

## 📋 Requirements

- iOS 16.0+ or visionOS 1.0+
- Xcode 15.0+
- Swift 5.9+
- For iOS: Device with A12 Bionic chip or later (for ARKit capabilities)
- For visionOS: Apple Vision Pro

## 🛠️ Setup and Installation

1. Clone the repository
2. Add your 3D anatomical models (USDZ format) to the `Shared/models` directory
3. Open `XR Anatomy.xcodeproj` in Xcode
4. Select your target device
5. Build and run the app

### Adding 3D Models

The app looks for USDZ model files in the `Shared/models` directory. These models are **not** included in the repository and must be added manually.

For proper rotation, models that should rotate around the Z-axis should be added to the list in `ModelType.swift`:

```swift
static let zAxisRotationModels: [String] = ["arteriesHead", "brain", "heart", "heart2K"]
```

## 🚀 Using the App

1. **Launch**: Open the app on your iOS device or Apple Vision Pro
2. **Connection**: Choose whether to host a session or join an existing one
3. **Model Selection**: Choose an anatomical model from the menu
4. **Placement**: Tap on a flat surface (iOS) or look at a position (visionOS) to place the model
5. **Manipulation**: Use gestures to rotate, scale, and move the models
6. **Collaboration**: All changes are synchronized in real-time with connected users

## 🔄 Multiplayer Collaboration

The app supports real-time collaboration between multiple users:

- **Host**: Create a new session that others can join
- **Join**: Connect to an existing session hosted by another user
- **Permissions**: Hosts can grant or revoke permission for viewers to modify models

## 📱 Platform-Specific Features

### iOS

- Uses ARKit for plane detection and model placement
- Tap on detected planes to place models
- AR coaching overlay helps users find flat surfaces

### visionOS

- Native spatial computing experience
- Place models in 3D space
- Full immersive experience with the anatomical models

## 🐛 Troubleshooting

- **Simulator Errors**: The app may show errors in the iOS simulator as the simulator doesn't fully support all AR features. Running on a physical device is recommended.
- **Missing Models**: Ensure you've placed USDZ model files in the `Shared/models` directory.
- **Connection Issues**: Make sure all devices are on the same Wi-Fi network for multiplayer collaboration.

## 📝 License

This project is available for educational use.

## 📚 Docset Ingestion

You can ingest an Apple .docset (e.g. Apple API Reference) for retrieval or fine-tuning.

1. Install Python dependencies:
   ```bash
   pip install -r requirements.txt
   ```
2. Configure your docset path:
   - Copy `docset_config.json.template` to `docset_config.json`
   - Edit `docset_config.json` and set `docset_path`, `index_path`, and `meta_path`
3. Generate the FAISS index:
   ```bash
   make docset-index
   ```
   This will read your `docset_config.json` and produce:
   - A FAISS index at the configured `index_path` (e.g., `data/docset_index.faiss`)
   - A metadata file at the configured `meta_path` (e.g., `data/docset_index.faiss.meta.json`)

3. Use the index for retrieval-augmented queries or convert metadata for fine-tuning datasets.

## 🔍 Querying the Docset Index

After ingestion, you can fetch relevant API docs for a query:

### Using config file:
```bash
make docset-query QUESTION="How do I create a UIView?"
```

### Or specifying paths explicitly:
```bash
make query-docset INDEX=data/docset_index.faiss \
                   META=data/docset_index.faiss.meta.json \
                   QUERY="How do I create a UIView?"
```

This will return the top matching documentation chunks from the Apple API Reference.
