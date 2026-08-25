# CredentioKit (Swift / Apple Platforms)

High-performance native Swift bindings for [Google Credentio](https://mediaprovenance.googlesource.com/credentio/) C2PA Content Credentials validator.

---

## 🚀 Overview

`CredentioKit` provides:
- **In-process C2PA validation**: Sub-millisecond core verification running directly via a C-ABI static XCFramework (`CredentioC.xcframework`).
- **Sendable & Actor-isolated**: Pure Swift 6 concurrency safety.
- **App Sandbox Compliant**: In-process engine requires zero child subprocesses or sandbox entitlements.
- **Pure Swift Fallback**: Compiles immediately with zero C++ toolchain requirements for CLI/crJSON workflows.
- **Built-in Format Detection**: `SupportedFormats` helper for image, video, audio, and document validation.
- **Cross-platform Apple support**: macOS 14.0+ and iOS 16.0+ (prebuilt binary targets macOS arm64; other platforms build from source).

---

## ⚡ Quick Start

### 1. Add to Swift Package Manager

Add `CredentioKit` to your dependencies in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ghchinoy/credentio-contributions.git", from: "0.1.1")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "CredentioKit", package: "credentio-contributions")
        ]
    )
]
```

> **Note on Prebuilt XCFramework:** The pre-compiled release binary currently targets **macOS (arm64)**. For Intel Mac (x86_64) or iOS architectures, compile the static XCFramework from source using `make build-swift`.

### 2. Local Source Build (Optional)

To compile the static XCFramework locally from Google Credentio source on macOS:

```bash
make build-swift
```

---

## 📖 Usage Example

```swift
import CredentioKit
import Foundation

// 1. Check format support
let fileURL = URL(fileURLWithPath: "photo.jpg")
guard SupportedFormats.isSupported(fileURL) else {
    print("Unsupported format: \(fileURL.pathExtension)")
    exit(1)
}

// 2. Initialize the actor-isolated native engine
let engine = CredentioNativeEngine(skipTrustChecks: true)

// 3. Validate a media file
let report = try await engine.read(url: fileURL)

if report.hasCredentials {
    print("Badge Status:     \(report.badge.rawValue)") // "signed", "unsigned", "invalid"
    print("Claim Generator:  \(report.primaryClaimGenerator ?? "Unknown")")
    print("Signer Issuer:    \(report.primarySignerIssuer ?? "Unknown")")
    if let coreTime = report.engineInternalElapsed {
        print("Core Engine Time: \(coreTime)")
    }
} else {
    print("No C2PA Content Credentials found.")
}
```
