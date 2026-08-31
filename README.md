# Credentio Contributions

[![CI](https://github.com/ghchinoy/credentio-contributions/actions/workflows/ci.yml/badge.svg)](https://github.com/ghchinoy/credentio-contributions/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Idiomatic, high-performance **Python**, **Go**, **Swift**, and **WebAssembly/TypeScript** bindings for [Google Credentio](https://mediaprovenance.googlesource.com/credentio/), the C2PA Content Credentials validator.

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
  - [Step 0: Clone Repositories](#step-0-clone-repositories)
  - [Step 1: Build Native Libraries](#step-1-build-native-libraries)
  - [Step 2: Python Usage](#step-2-python-usage)
  - [Step 3: Go Usage](#step-3-go-usage)
  - [Step 4: Swift Usage](#step-4-swift-usage)
  - [Step 5: WebAssembly / TypeScript Usage](#step-5-webassembly--typescript-usage)
  - [Step 6: Command-Line Interface (CLI)](#step-6-command-line-interface-cli)
- [Distribution Status](#distribution-status)
- [Documentation Portal](#documentation-portal)
- [Contributing](#contributing)
- [License & Disclaimer](#license--disclaimer)

---

## Overview

[Google Credentio](https://mediaprovenance.googlesource.com/credentio/) is an open-source C++ library for verifying [C2PA Content Credentials](https://c2pa.org/) locally in-process without network overhead.

This repository provides language bindings built on top of a unified C-ABI bridge (`libcredentio_c` / `CredentioC.xcframework` / `credentio.wasm`), bringing sub-millisecond local provenance validation to:

- 🌐 **WebAssembly/TypeScript (`@ghchinoy/credentio-wasm`)**: Isomorphic single-threaded WebAssembly package for browsers, web workers, Node.js, and edge runtimes.
- 🐍 **Python (`credentio`)**: `cffi`-based library with typed dataclasses, context managers, and zero runtime dependencies.
- 🐹 **Go (`github.com/ghchinoy/credentio-contributions/go`)**: `cgo`-based package with thread-safe validators, `encoding/json` models, and functional options.
- 🍏 **Swift (`CredentioKit`)**: Actor-isolated Swift 6 package supporting macOS 14+ and iOS 16+ (prebuilt binaries currently ship macOS arm64; other targets build from source).

---

## Prerequisites

- **Operating System:** macOS (Apple Silicon or Intel) or Linux (x86_64, aarch64)
- **C++ Compiler:** Clang supporting C++20
- **Build System:** [Bazel 7.0+](https://bazel.build/) (or `bazelisk`)
- **Language Toolchains:**
  - Python 3.9+ with `pip`
  - Go 1.21+
  - Xcode 16+ (for Swift / macOS / iOS builds)
  - Node.js 18+ with `npm` (for WebAssembly / TypeScript SDK)

> **Note on Prebuilt Binaries:** Pre-compiled release binaries currently target **macOS (arm64)** and **Linux (x86_64)**. Other architectures (such as Intel Mac, Linux aarch64, or iOS devices) can be compiled directly from source using the prerequisites above.

---

## Quick Start

### Step 0: Clone Repositories

Because Credentio is developed at `HEAD`, clone the upstream repository alongside `credentio-contributions` and check out the validated commit:

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

> **Note:** The build scripts automatically search for Credentio in `../credentio`, `~/projects/credentio`, or `/workspace/credentio`. You can override this by setting `export CREDENTIO_DIR="/path/to/credentio"`.

---

### Step 1: Build Native Libraries

```bash
# Build the dynamic shared library (for Python and Go):
make build-lib

# Build the static XCFramework (for Swift / Apple platforms):
make build-swift
```

---

### Step 2: Python Usage

Install the package in your active Python environment:
```bash
make python-install
```

Validate a media file:
```python
from credentio import Validator

# Initialize a reusable validator instance
with Validator(skip_trust_checks=True) as validator:
    report = validator.validate_file("photo.jpg")

    if report.has_credentials:
        print(f"Status:     {report.badge.value.upper()}")  # 'SIGNED', 'UNSIGNED', 'INVALID'
        print(f"Generator:  {report.active_manifest.claim_generator}")
        print(f"Signer:     {report.active_manifest.signature.issuer}")
        print(f"Core Time:  {report.core_seconds * 1000:.2f} ms")
    else:
        print("No C2PA Content Credentials found.")
```

Run Python tests:
```bash
make python-test
```

---

### Step 3: Go Usage

```go
package main

import (
	"fmt"
	"log"

	"github.com/ghchinoy/credentio-contributions/go"
)

func main() {
	validator, err := credentio.NewValidator(credentio.WithSkipTrustChecks(true))
	if err != nil {
		log.Fatalf("Failed to initialize validator: %v", err)
	}
	defer validator.Close()

	report, err := validator.ValidateFile("photo.jpg", "image/jpeg")
	if err != nil {
		log.Fatalf("Validation error: %v", err)
	}

	if report.HasCredentials {
		fmt.Printf("Status:     %s\n", report.Badge())
		fmt.Printf("Generator:  %s\n", report.ActiveManifest.ClaimGenerator)
		fmt.Printf("Signer:     %s\n", report.ActiveManifest.Signature.Issuer)
		fmt.Printf("Core Time:  %.2f ms\n", report.CoreSeconds*1000)
	} else {
		fmt.Println("No Content Credentials found.")
	}
}
```

Run Go tests:
```bash
make go-test
```

---

### Step 4: Swift Usage

Add `CredentioKit` to your `Package.swift`:

```swift
import CredentioKit
import Foundation

let engine = CredentioNativeEngine(skipTrustChecks: true)
let report = try await engine.read(url: URL(fileURLWithPath: "photo.jpg"))

if report.hasCredentials {
    print("Status:    \(report.badge.rawValue.uppercased())")
    print("Generator: \(report.activeManifest?.claimGenerator ?? "Unknown")")
    print("Signer:    \(report.activeManifest?.signature?.issuer ?? "Unknown")")
}
```

Run Swift tests:
```bash
make swift-test
```

---

### Step 5: WebAssembly / TypeScript Usage

Install the package (or release tarball):
```bash
npm install @ghchinoy/credentio-wasm
# or from release tarball:
# npm install https://github.com/ghchinoy/credentio-contributions/releases/download/v0.1.8/ghchinoy-credentio-wasm-0.1.8.tgz
```

Validate a media blob or file in TypeScript / JavaScript:
```typescript
import { CredentioValidator } from '@ghchinoy/credentio-wasm';

// Initialize the single-threaded WebAssembly engine
const validator = await CredentioValidator.create({ skipTrustChecks: true });

try {
  const report = await validator.validateBlob(fileBlob);

  if (report.hasCredentials) {
    console.log(`Status:    ${report.badge.toUpperCase()}`); // 'SIGNED', 'UNSIGNED', 'INVALID'
    console.log(`Generator: ${report.activeManifest?.claimGenerator}`);
    console.log(`Signer:    ${report.activeManifest?.signature?.issuer}`);
    console.log(`Core Time: ${(report.coreSeconds * 1000).toFixed(2)} ms`);
  } else {
    console.log('No C2PA Content Credentials found.');
  }
} finally {
  validator.dispose();
}
```

Run TypeScript and WebAssembly tests:
```bash
make wasm-test
```

---

### Step 6: Command-Line Interface (CLI)

Each language provides a standalone command-line validator implementing standard exit codes (`0=Signed`, `1=Unsigned`, `2=Invalid`):

```bash
# Python CLI:
credentio validate photo.jpg [--json]

# Go CLI:
./bin/credentio validate photo.jpg [-json]

# Swift CLI:
cd swift && swift run credentio-cli validate ../photo.jpg [--json]
```

See the [CLI Tutorial](https://ghchinoy.github.io/credentio-contributions/cli/) for a complete hands-on guide.

---

## Distribution Status

Pre-compiled binary releases and source packages are distributed across multiple package ecosystems:

- **WebAssembly/TypeScript (@ghchinoy/credentio-wasm):** Pre-compiled single-threaded WebAssembly package and binaries attached to GitHub Releases (`ghchinoy-credentio-wasm-0.1.8.tgz`, `credentio.wasm`, `credentio.js`). npm registry publication will follow upstream coordination.
- **Swift (CredentioKit):** Swift Package Manager remote binary package linking pre-compiled `CredentioC.xcframework` (macOS arm64 prebuilt today; iOS and universal binaries build from source).
- **Python (credentio):** Pre-compiled binary wheels attached to GitHub Releases (macOS arm64 and Linux x86_64). PyPI registry publication is coming soon.
- **Go:** Standard Go module with automated prebuilt library download via `make fetch-lib` (macOS arm64 and Linux x86_64) or direct compilation from source.

---

## Documentation Portal

This project includes an interactive [Astro Starlight](https://starlight.astro.build/) documentation site:

```bash
make docs-serve
```

- [Live Web Validator](https://credentio-validator.web.app/): Standalone in-browser C2PA validator app powered by `@ghchinoy/credentio-wasm`.
- [Developer Guide](docs/developers_guide.md): Comprehensive guide to the C-ABI bridge, XCFramework build, and architecture.
- [ADR-0001: Shared C-ABI Strategy](docs/adr/0001-shared-c-abi-bindings.md): Architectural decision record for multi-language FFI.
- [ADR-0002: WebAssembly / Emscripten Bindings](docs/adr/0002-webassembly-emscripten-bindings.md): Architectural decision record for browser and Node.js WebAssembly compilation.
- [Maintenance & Drift Detection](https://ghchinoy.github.io/credentio-contributions/maintenance/): Authoritative baseline pinning (`.credentio-pin`), `make check-drift`, and automated CI tracking.

---

## Contributing

Contributions, bug reports, and optimizations are welcome!

Please review our [Contributing Guidelines](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md) before submitting a pull request or opening an issue.

---

## License & Disclaimer

Credentio Contributions is licensed under the **Apache License, Version 2.0**. See [LICENSE](LICENSE) for more information.

### Disclaimer
*This project is an open-source community contribution and is not an officially supported Google product. This project is not eligible for the Google Open Source Software Vulnerability Rewards Program.*
