# CredentioKit (Swift / Apple Platforms)

High-performance native Swift bindings for [Google Credentio](https://mediaprovenance.googlesource.com/credentio/) C2PA Content Credentials validator.

---

## 🚀 Overview

`CredentioKit` provides:
- **In-process C2PA validation**: Sub-millisecond core verification running directly via a C-ABI static XCFramework (`CredentioC.xcframework`).
- **Sendable & Actor-isolated**: Pure Swift 6 concurrency safety.
- **Cross-platform Apple support**: macOS 14.0+ and iOS 16.0+.
- **Engine-agnostic data models**: Standardized `ProvenanceReport` and `Manifest` models.

---

## ⚡ Quick Start

### 1. Build Native Credentio Static XCFramework
From the repository root on macOS:

```bash
make build-swift
```

### 2. Add to Swift Package Manager
`CredentioKit` is currently distributed as a local package built from source (remote registry releases with pre-compiled XCFrameworks are planned for future releases).

After running `make build-swift`, reference the local package directory in your `Package.swift`:

```swift
dependencies: [
    .package(path: "../credentio-contributions/swift")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "CredentioKit", package: "swift")
        ]
    )
]
```

---

## 📖 Usage Example

```swift
import CredentioKit
import Foundation

// 1. Initialize the actor-isolated native engine
let engine = CredentioNativeEngine(skipTrustChecks: true)

// 2. Validate a media file
let fileURL = URL(fileURLWithPath: "photo.jpg")
let report = try await engine.read(url: fileURL)

if report.hasCredentials {
    print("Badge Status:     \(report.badge.rawValue)") // "signed", "unsigned", "invalid"
    print("Claim Generator:  \(report.activeManifest?.claimGenerator ?? "Unknown")")
    print("Signer Issuer:    \(report.activeManifest?.signature?.issuer ?? "Unknown")")
    if let coreTime = report.engineInternalElapsed {
        print("Core Engine Time: \(coreTime)")
    }
} else {
    print("No C2PA Content Credentials found.")
}
```
