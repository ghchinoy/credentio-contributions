# Developer Guide: Credentio Python, Go, and Swift Bindings

This guide details the internal architecture, C-ABI interface, upstream Credentio setup, build workflows, and packaging for the Python, Go, and Swift bindings of Google Credentio.

---

## 1. Prerequisite: Getting Google Credentio

All language bindings in this repository depend on Google's C++20 [Credentio library](https://mediaprovenance.googlesource.com/credentio/). Because Credentio is actively developed at `HEAD` on Google's repository, the build scripts use an **overlay pattern** against a local Credentio checkout.

### Step 1: Clone Google Credentio
Clone the official upstream repository alongside `credentio-contributions`:

```bash
# Clone Credentio from Google's source repository:
git clone https://mediaprovenance.googlesource.com/credentio
```

### Step 2: Check Out the Validated Commit
Credentio recommends living at `HEAD`, but upstream changes can introduce breaking schema or C++ API updates without notice. This repository is validated against commit **`4ac69fc`**:

```bash
cd credentio
git checkout 4ac69fc58256d3871e765f615254373e19e250e9
```

### Step 3: Configure Discovery (or Set `CREDENTIO_DIR`)
The build scripts automatically search for Credentio in:
1. `$CREDENTIO_DIR` (environment variable override)
2. `~/projects/credentio`
3. `../credentio` (sibling directory)
4. `/workspace/credentio`

If your Credentio checkout is located in another directory, export the environment variable:

```bash
export CREDENTIO_DIR="/path/to/my/credentio"
```

### Step 4: Verify Upstream Build Tools
Credentio requires:
- **Clang** with C++20 support
- **Bazel 7.0+** (or `bazelisk`)

You can verify your upstream toolchain by running Credentio's native test suite:
```bash
cd /path/to/credentio
bazel test ...
```

---

## 2. C-ABI Bridge (`native/`)

To insulate Python, Go, and Swift from C++20 standard library templates, Protocol Buffers, and Abseil data structures, a unified `extern "C"` wrapper is implemented in `native/credentio_c.h` and `native/credentio_c.cc`.

### Functions Exported:
- `cr_validator_create(claim_pem, tsa_pem, skip_trust)`: Initializes an `AssetValidatorImpl` instance with `DefaultCryptoReadHandler`.
- `cr_validator_free(v)`: Releases native validator resources.
- `cr_validate_file(v, path, media_type, out_status)`: Validates a file on disk using `riegeli::CFileReader` and formats results as crJSON.
- `cr_validate_bytes(v, bytes, count, media_type, out_status)`: Validates in-memory data using `riegeli::StringReader` and formats results as crJSON.
- `cr_last_error(v)`: Returns the most recent error message string.
- `cr_last_internal_seconds(v)`: Returns sub-millisecond core engine validation duration (measured using `std::chrono::high_resolution_clock`).
- `cr_string_free(str)`: Frees malloc'd crJSON strings.

---

## 3. Shared Library Build Workflow (`scripts/build-shared-lib.sh`)

Used by Python (`cffi`) and Go (`cgo`):

1. Overlays `native/*` into the local Credentio checkout under `bindings_c/`.
2. Runs `bazel build //bindings_c:libcredentio_c`.
   - `linkshared = True` ensures all transitive C++ static dependencies (BoringSSL, Tink, Protobuf, Abseil, Riegeli, nlohmann_json) are resolved and linked into a monolithic dynamic library (`.dylib` on macOS, `.so` on Linux).
3. Stages the shared library and headers into:
   - `python/src/credentio/lib/` and `python/src/credentio/include/`
   - `go/lib/` and `go/include/`

To build:
```bash
make build-lib
```

---

## 4. Static XCFramework Build Workflow (`scripts/build-swift-xcframework.sh`)

Used by Swift (`CredentioKit`):

1. Overlays `native/*` into Credentio under `bindings_c/`.
2. Runs `bazel build //bindings_c:credentio_c`.
3. Queries the transitive static library closure using Bazel `cquery` on `CcInfo.linking_context.linker_inputs`.
4. Merges all static archive dependencies with `libtool -static` into a monolithic `libCredentioC.a`.
5. Packages `swift/CredentioC.xcframework` using `xcodebuild -create-xcframework`.

To build:
```bash
make build-swift
```

---

## 5. Python Binding (`python/`)

- Implemented using `cffi` out-of-line ABI mode.
- `_ffi.py` dynamically locates and loads the bundled `libcredentio_c` shared library.
- `models.py` normalizes raw crJSON payloads into type-annotated dataclasses (`ProvenanceReport`, `Manifest`, `SignatureInfo`, `Assertion`, `ValidationStatus`).
- `validator.py` exposes the `Validator` class with context manager support.

To test:
```bash
make python-test
```

---

## 6. Go Binding (`go/`)

- Implemented using standard `cgo`.
- `credentio.go` binds `credentio_c.h` with thread-safe mutex-protected method receivers.
- `models.go` uses `encoding/json` to deserialize crJSON payloads into Go structs.

To test:
```bash
make go-test
```

---

## 7. Swift Binding (`swift/`)

- Implemented as a standalone SwiftPM package (`CredentioKit`) for macOS 14+ and iOS 16+.
- `CredentioNativeEngine.swift` is an `actor` providing thread safety under Swift 6 strict concurrency.
- A `Sendable` `CredentioHandle` class manages C pointer lifecycle.
- `Package.swift` declares `linkerSettings: [.linkedLibrary("c++")]` to automatically resolve C++ standard library runtime symbols for downstream apps.

To test:
```bash
make swift-test
```

---

## 8. Command-Line Tools & Scripts

All three bindings expose thin CLI entry points:
- **Python:** `credentio.cli:main` registered as console script `credentio` via `pyproject.toml`.
- **Go:** `go/cmd/credentio/main.go` producing executable binary `credentio`.
- **Swift:** `swift/Sources/credentio-cli` built with `swift-argument-parser` producing `credentio-cli`.

See the [CLI Tutorial](https://ghchinoy.github.io/credentio-contributions/cli/) on the documentation site for execution patterns and shell exit codes.
