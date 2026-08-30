# 0002: WebAssembly and TypeScript SDK architecture via Bazel and Emscripten

- Status: Accepted
- Date: 2026-08-30

## Context

Google Credentio is an open-source C++20 library developed by Google for high-performance C2PA Content Credentials validation. While existing language bindings in this repository provide native bindings for Python (`cffi`), Go (`cgo`), and Apple platforms (`CredentioKit` via XCFramework), client-side web applications, browser extensions, Electron desktops, and modern JavaScript runtimes require a native JavaScript and TypeScript solution.

Traditional web approaches to C2PA verification either delegate verification to remote backend servers (introducing latency, egress bandwidth costs, and privacy concerns for user media) or rely on heavy pure-JavaScript parsers that lack full cryptographic validation support and drift from upstream C2PA implementations.

We need an isomorphic, local-first solution that compiles the authoritative C++20 Credentio validation engine directly into WebAssembly (WASM), providing fast in-browser and server-side verification with full schema parity and zero network leakage.

## Decision

1. **Bazel and Emscripten Compilation Pipeline:**
   Compile `native/credentio_c.cc` and the upstream Google Credentio C++20 dependency graph into WebAssembly (`credentio.wasm`) and an ES module factory (`credentio.js`) using Bazel with the `@emsdk` toolchain (`--platforms=@emsdk//:platform_wasm`). The build executes inside a reproducible container environment (supporting Apple `container`, Docker, and Podman), producing an optimized WASM binary with `-std=c++20`, `-O3`, `-sMODULARIZE=1`, `-sEXPORT_ES6=1`, `-sALLOW_MEMORY_GROWTH=1`, `-sENVIRONMENT=web,webview,worker,node`, and `-pthread` atomic support.

2. **Unified C-ABI Export Surface:**
   Export the exact same `extern "C"` ABI functions used by Python, Go, and Swift:
   - `_cr_validator_create(claim_signer_pem, tsa_pem, skip_trust)`
   - `_cr_validator_free(validator_ptr)`
   - `_cr_validate_bytes(validator_ptr, bytes_ptr, count, media_type_ptr, out_status_ptr)`
   - `_cr_validate_file(validator_ptr, file_path_ptr, media_type_ptr, out_status_ptr)`
   - `_cr_last_error(validator_ptr)`
   - `_cr_last_internal_seconds(validator_ptr)`
   - `_cr_string_free(str_ptr)`
   - `_cr_version()`

3. **Dual-Layer TypeScript SDK Architecture:**
   Structure the `@ghchinoy/credentio-wasm` package in `wasm/` into two distinct layers:
   - **Low-Level Bridge (`CredentioWasmBridge`):** Manages manual WebAssembly linear memory allocations (`_malloc`, `_free`), buffer copying via `HEAPU8.set()`, UTF-8 string marshalling, and raw JSON extraction.
   - **High-Level Validator (`CredentioValidator`):** Provides an ergonomic, asynchronous API with `validateBytes(buffer)` and `validateBlob(blob)`, automatic MIME sniffing, lifecycle tracking, and explicit resource disposal via `[Symbol.dispose]()` and `close()`.

4. **crJSON Schema Resilience and Cross-Language Parity:**
   Implement a resilient crJSON parser (`parseCrJSON`) that handles both C2PA v1 (`claim`) and C2PA v2 (`claim.v2`) schemas, dictionary or array manifest stores, X.509 certificate chains, and assertion classifications. Data models (`ProvenanceReport`, `Manifest`, `Assertion`, `ValidationStatus`, `BadgeState`) strictly mirror the schemas defined in Python, Go, and Swift.

5. **Universal Runtime Support:**
   Implement a universal loader that detects the active JavaScript runtime environment (Browser window, Web Worker, Node.js `node:fs`, or Edge runtime) and resolves the `.wasm` binary seamlessly without platform-specific build targets.

## Consequences

- **Local-First Privacy:** Media files are validated entirely within the local execution context (client browser or local Node.js process) with zero byte transmission over the network.
- **Fast Execution:** Core verification executes locally in WebAssembly, matching native C++ validation behavior after initial module instantiation.
- **Single Source of Truth:** Upstream algorithm refinements in Google Credentio C++20 automatically propagate to WebAssembly through the shared C-ABI interface.
- **Explicit Memory Safety:** Strict pointer tracking and explicit disposal prevent WebAssembly linear memory leaks during high-throughput batch validation.
