---
title: Quick Start
description: Build native Credentio libraries and run Python, Go, and Swift validation in minutes.
---

Follow this guide to set up Google Credentio, compile the native libraries, and validate C2PA assets across Python, Go, or Swift.

---

## 1. Prerequisites

- **Operating System:** macOS (Apple Silicon or Intel) or Linux (x86_64 or aarch64)
- **C++ Toolchain:** Clang with C++20 support
- **Build System:** [Bazel 7.0+](https://bazel.build/) (or `bazelisk`)
- **Language Toolchains:**
  - Python 3.9+ with `pip`
  - Go 1.21+
  - Xcode 16+ (for Swift / Apple platforms)

---

## 2. Clone Repositories

Because Credentio is developed at `HEAD`, clone the official upstream repository alongside `credentio-contributions` and check out the validated commit (`4ac69fc`):

```bash
# 1. Clone Google Credentio:
git clone https://mediaprovenance.googlesource.com/credentio
cd credentio
git checkout 4ac69fc58256d3871e765f615254373e19e250e9
cd ..

# 2. Clone Credentio Contributions:
git clone https://github.com/ghchinoy/credentio-contributions.git
cd credentio-contributions
```

---

## 3. Build Native Libraries

```bash
# Build the dynamic shared library (for Python and Go):
make build-lib

# Build the static XCFramework (for Swift / Apple platforms):
make build-swift
```

---

## 4. Python Quick Start

### Installation
```bash
make python-install
```

### Validating an Asset File
Create `example.py`:

```python
from credentio import Validator

# 1. Initialize the validator
with Validator(skip_trust_checks=True) as validator:
    # 2. Validate a media file
    report = validator.validate_file("sample.jpg")

    if report.has_credentials:
        print(f"Overall Status:   {report.badge.value.upper()}")
        print(f"Claim Generator:  {report.active_manifest.claim_generator}")
        print(f"Signer Issuer:    {report.active_manifest.signature.issuer}")
        print(f"Core Engine Time: {report.core_seconds * 1000:.2f} ms")
    else:
        print("No C2PA Content Credentials found in this asset.")
```

Run the script:
```bash
python3 example.py
```

---

## 5. Go Quick Start

Ensure the native shared library is available (via `make fetch-lib` or Step 3 `make build-lib`), then create `main.go`:

```go
package main

import (
	"fmt"
	"log"

	"github.com/ghchinoy/credentio-contributions/go"
)

func main() {
	// 1. Initialize a thread-safe validator
	validator, err := credentio.NewValidator(
		credentio.WithSkipTrustChecks(true),
	)
	if err != nil {
		log.Fatalf("Failed to initialize Credentio validator: %v", err)
	}
	defer validator.Close()

	// 2. Validate an asset
	report, err := validator.ValidateFile("sample.mp4", "video/mp4")
	if err != nil {
		log.Fatalf("Validation failed: %v", err)
	}

	if report.HasCredentials {
		fmt.Printf("Status:           %s\n", report.Badge())
		fmt.Printf("Claim Generator:  %s\n", report.ActiveManifest.ClaimGenerator)
		fmt.Printf("Signer Issuer:    %s\n", report.ActiveManifest.Signature.Issuer)
		fmt.Printf("Core Engine Time: %.2f ms\n", report.CoreSeconds*1000)
	} else {
		fmt.Println("No Content Credentials found.")
	}
}
```

Run the program:
```bash
CGO_ENABLED=1 go run main.go
```

---

## 6. Swift Quick Start

Add `CredentioKit` to your `Package.swift`:

```swift
import CredentioKit
import Foundation

let engine = CredentioNativeEngine(skipTrustChecks: true)
let report = try await engine.read(url: URL(fileURLWithPath: "sample.jpg"))

if report.hasCredentials {
    print("Status:           \(report.badge.rawValue.uppercased())")
    print("Claim Generator:  \(report.activeManifest?.claimGenerator ?? "Unknown")")
    print("Signer Issuer:    \(report.activeManifest?.signature?.issuer ?? "Unknown")")
}
```
