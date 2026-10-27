# Sift

A dark-mode SwiftUI app for macOS and iOS that helps you find and organise your files and photos.

## Structure
- `project.yml`: [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec that generates `Sift.xcodeproj`
- `Sources/Shared/`: models, theme and views shared by both platforms
- `Sources/Mac/`: macOS file browsing and storage
- `Sources/iOS/`: photo library access

Deployment targets: macOS 14.0 and iOS 17.0.

## Build
```bash
brew install xcodegen
xcodegen generate
open Sift.xcodeproj
```

Pick a scheme for macOS or iOS, set your development team in Xcode's Signing settings, and run.

## Notes
The `.app` bundle and per-user Xcode settings aren't included; Xcode creates them when you build.

## Screenshots
Not added yet.
