---
title: Swift Package Reference (CredentioKit)
description: API documentation and usage patterns for the CredentioKit Swift package.
---

`CredentioKit` provides high-performance, actor-isolated C2PA verification for Apple platforms (macOS 14.0+ and iOS 16.0+), powered in-process by Google Credentio.

---

## 1. Installation

### Swift Package Manager
Add `CredentioKit` to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/google/credentio-contributions.git", from: "0.1.0")
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

---

## 2. Compiling the Native XCFramework

`CredentioKit` uses `CredentioC.xcframework` (a static C-ABI archive) to execute Credentio directly in-process with zero subprocess overhead.

To build the static XCFramework:

```bash
# In the credentio-contributions repository:
make build-swift
```

---

## 3. The `CredentioNativeEngine` Actor

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

## 4. Models and Types

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

## 5. Standalone crJSON Deserializer

If you obtain crJSON strings from external sources (such as CLI logs or network payloads), you can deserialize them into a typed `ProvenanceReport`:

```swift
let report = CredentioCrjsonMapper.mapReport(
    json: rawCrjsonString,
    mediaType: "image/jpeg",
    elapsed: .milliseconds(4)
)
```
