---
title: Swift Package Reference (CredentioKit)
description: API documentation, SupportedFormats, App Sandbox compliance, and SwiftUI integration for CredentioKit.
---

`CredentioKit` provides high-performance, actor-isolated C2PA verification for Apple platforms (macOS 14.0+ and iOS 16.0+), powered in-process by Google Credentio.

---

## 1. Installation

### Remote Package Dependency (Recommended)

Add `CredentioKit` to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ghchinoy/credentio-contributions.git", from: "0.1.5")
],
targets: [
    .target(
        name: "MyAppleApp",
        dependencies: [
            .product(name: "CredentioKit", package: "credentio-contributions")
        ]
    )
]
```

> **Note on Prebuilt XCFramework:** The pre-compiled release binary currently targets **macOS (arm64)**. For Intel Mac (x86_64) or iOS architectures, compile the static XCFramework from source using `make build-swift`.

### Pure Swift vs. Native In-Process Engine

`CredentioKit` is designed to be modular:
- **Pure Swift Mode:** Compiles out of the box with zero C++ toolchain requirements. In pure Swift mode, `CredentioKit` provides all data models, format utilities, and `CredentioCLIEngine` (invoking the `c2pa_validate` CLI subprocess).
- **Native In-Process Mode:** When linked against `CredentioC.xcframework` (via remote package or local `make build-swift`), `CredentioNativeEngine` executes directly in-process with sub-millisecond core verification.

### Local Source Build (Optional)

To compile the static XCFramework locally from Google Credentio source on macOS:

```bash
make build-swift
```

---

## 2. The `CredentioNativeEngine` Actor

### Initialization
`CredentioNativeEngine` is an actor, guaranteeing compiler-enforced thread safety under Swift 6 strict concurrency.

```swift
import CredentioKit
import Foundation

// Initialize with testing configuration (bypasses trust checks)
let engine = CredentioNativeEngine(skipTrustChecks: true)

// Initialize with production trust anchor PEM files
let prodEngine = CredentioNativeEngine(
    claimSignerTrustPath: "/path/to/claim_roots.pem",
    tsaTrustPath: "/path/to/tsa_roots.pem",
    skipTrustChecks: false
)
```

### Validating a Media Asset
```swift
let assetURL = URL(fileURLWithPath: "sample.jpg")

do {
    let report = try await engine.read(url: assetURL)

    if report.hasCredentials {
        print("Status:           \(report.badge.rawValue.uppercased())")
        print("Claim Generator:  \(report.activeManifest?.claimGenerator ?? "Unknown")")
        print("Signer Issuer:    \(report.activeManifest?.signature?.issuer ?? "Unknown")")
        
        if let coreElapsed = report.engineInternalElapsed {
            print("Core Engine Time: \(coreElapsed)")
        }
    } else {
        print("No C2PA Content Credentials found.")
    }
} catch {
    print("Validation error: \(error.localizedDescription)")
}
```

---

## 3. macOS and iOS App Sandbox Compatibility

Apple App Store and sandboxed desktop environments enforce strict security boundaries regarding process creation and entitlements:

- **`CredentioNativeEngine` (App Sandbox Compliant):** Links directly to the static `CredentioC.xcframework` library and executes inside your app address space. It requires zero subprocess entitlements, makes no out-of-process system calls, and is 100% compliant with the macOS and iOS App Sandbox.
- **`CredentioCLIEngine` (Developer & Tooling):** Spawns the `c2pa_validate` binary via Foundation `Process`. This engine is designed for CLI utilities and unsandboxed developer environments.

---

## 4. Format Detection with `SupportedFormats`

`CredentioKit` includes built-in file format and MIME type resolution across images, video, audio, and documents:

```swift
import CredentioKit

let imageURL = URL(fileURLWithPath: "photo.jpg")

// Inspect MIME type
let mimeType = SupportedFormats.mediaType(for: imageURL) // "image/jpeg"

// Inspect category
let category = SupportedFormats.category(for: imageURL)  // .image

// Check format support
if SupportedFormats.isSupported(imageURL) {
    print("Format is supported by Credentio")
}
```

### Supported Categories:
- **`Category.image`:** JPEG, PNG, HEIC, HEIF, WebP, AVIF, TIFF, DNG
- **`Category.video`:** MP4, MOV, QuickTime, AVI, WebM
- **`Category.audio`:** MP3, WAV, M4A, AAC, FLAC, OGG
- **`Category.document`:** PDF, DOCX, XLSX, PPTX

---

## 5. SwiftUI Integration Example

Here is a complete pattern for integrating `CredentioNativeEngine` into a modern SwiftUI application using `@Observable` and Swift 6 concurrency:

```swift
import CredentioKit
import SwiftUI

@Observable
@MainActor
final class ProvenanceInspectorViewModel {
    var report: ProvenanceReport?
    var isLoading = false
    var errorMessage: String?

    private let engine = CredentioNativeEngine(skipTrustChecks: true)

    func inspect(fileURL: URL) async {
        guard SupportedFormats.isSupported(fileURL) else {
            errorMessage = "Unsupported format: \(fileURL.pathExtension)"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            report = try await engine.read(url: fileURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProvenanceInspectorView: View {
    @State private var viewModel = ProvenanceInspectorViewModel()
    let assetURL: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isLoading {
                ProgressView("Inspecting credentials...")
            } else if let report = viewModel.report {
                HStack {
                    Text("Badge:")
                    Text(report.badge.rawValue.uppercased())
                        .fontWeight(.bold)
                }
                if let generator = report.primaryClaimGenerator {
                    Text("Generator: \(generator)")
                }
                if let signer = report.primarySignerIssuer {
                    Text("Signer: \(signer)")
                }
            } else if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
        .task {
            await viewModel.inspect(fileURL: assetURL)
        }
    }
}
```

---

## 6. Models and Types

### `ProvenanceReport`
```swift
public struct ProvenanceReport: Sendable, Equatable {
    public var engineID: String                   // "credentio-native"
    public var engineName: String                 // "Credentio Native (In-Process)"
    public var hasCredentials: Bool
    public var elapsed: Duration                  // Wall-clock time
    public var engineInternalElapsed: Duration?   // Sub-millisecond core C++ time
    public var mediaType: String?
    public var specVersion: String?
    public var activeManifest: Manifest?
    public var ingredientManifests: [Manifest]
    public var rawJSON: String?
    public var badge: CredentialBadgeState        // .signed, .unsigned, .invalid
    
    // Convenience Accessors
    public var isVerified: Bool                   // True if badge == .signed
    public var isInvalid: Bool                    // True if badge == .invalid
    public var primaryClaimGenerator: String?
    public var primarySignerIssuer: String?
}
```

### `Manifest`
```swift
public struct Manifest: Sendable, Equatable, Identifiable {
    public var label: String
    public var title: String?
    public var format: String?
    public var claimGenerator: String?
    public var isUpdateManifest: Bool
    public var signature: SignatureInfo?
    public var assertions: [Assertion]
    public var validationStatuses: [ValidationStatus]
}
```

---

## 7. Standalone crJSON Deserializer

If you obtain crJSON strings from external sources (such as CLI logs or network payloads), you can deserialize them into a typed `ProvenanceReport`:

```swift
let report = CredentioCrjsonMapper.mapReport(
    json: rawCrjsonString,
    mediaType: "image/jpeg",
    elapsed: .milliseconds(4)
)
```
