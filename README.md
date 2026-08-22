# Credentio Contributions

[![CI](https://github.com/google/credentio-contributions/actions/workflows/ci.yml/badge.svg)](https://github.com/google/credentio-contributions/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Idiomatic, high-performance **Python**, **Go**, and **Swift** bindings for [Google Credentio](https://mediaprovenance.googlesource.com/credentio/), the C2PA Content Credentials validator.

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
- [Distribution Status](#distribution-status)
- [Documentation Portal](#documentation-portal)
- [Contributing](#contributing)
- [License & Disclaimer](#license--disclaimer)

---

## Overview

[Google Credentio](https://mediaprovenance.googlesource.com/credentio/) is an open-source C++ library for verifying [C2PA Content Credentials](https://c2pa.org/) locally in-process without network overhead.

This repository provides language bindings built on top of a unified C-ABI bridge (`libcredentio_c` / `CredentioC.xcframework`), bringing sub-millisecond local provenance validation to:

- 🐍 **Python (`credentio`)**: `cffi`-based library with typed dataclasses, context managers, and zero runtime dependencies.
- 🐹 **Go (`github.com/google/credentio/go`)**: `cgo`-based package with thread-safe validators, `encoding/json` models, and functional options.
- 🍏 **Swift (`CredentioKit`)**: Actor-isolated Swift 6 package for macOS 14+ and iOS 16+ via a native static XCFramework.

---

## Prerequisites

- **Operating System:** macOS (Apple Silicon or Intel) or Linux (x86_64, aarch64)
- **C++ Compiler:** Clang supporting C++20
- **Build System:** [Bazel 7.0+](https://bazel.build/) (or `bazelisk`)
- **Language Toolchains:**
  - Python 3.9+ with `pip`
  - Go 1.21+
  - Xcode 16+ (for Swift / macOS / iOS builds)

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
git clone https://github.com/google/credentio-contributions.git
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

	"github.com/google/credentio/go"
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

### Step 5: Command-Line Interface (CLI)

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

Packages in this repository are currently distributed as **source distributions built against local Credentio checkouts**. 

Pre-compiled binary wheels for PyPI and registered modules for package registries are planned for future releases as the upstream C2PA C-ABI stabilizes.

---

## Documentation Portal

This project includes an interactive [Astro Starlight](https://starlight.astro.build/) documentation site:

```bash
make docs-serve
```

- [Developer Guide](docs/developers_guide.md) — Comprehensive guide to the C-ABI bridge, XCFramework build, and architecture.
- [ADR-0001: Shared C-ABI Strategy](docs/adr/0001-shared-c-abi-bindings.md) — Architectural decision record for multi-language FFI.

---

## Contributing

Contributions, bug reports, and optimizations are welcome!

Please review our [Contributing Guidelines](CONTRIBUTING.md) and [Code of Conduct](CODE_OF_CONDUCT.md) before submitting a pull request or opening an issue.

---

## License & Disclaimer

Credentio Contributions is licensed under the **Apache License, Version 2.0**. See [LICENSE](LICENSE) for more information.

### Disclaimer
*This project is an open-source community contribution and is not an officially supported Google product. This project is not eligible for the Google Open Source Software Vulnerability Rewards Program.*
