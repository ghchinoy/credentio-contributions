<!--
Copyright 2026 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-->

# @ghchinoy/credentio-wasm

> Isomorphic WebAssembly and TypeScript SDK for [Google Credentio](https://mediaprovenance.googlesource.com/credentio) C2PA Content Credentials verification.

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.7+-blue.svg)](https://www.typescriptlang.org/)
[![WebAssembly](https://img.shields.io/badge/WebAssembly-WASM-654FF0.svg)](https://webassembly.org/)

This package brings the high-performance C++20 C2PA validation engine from Google Credentio to the JavaScript and TypeScript ecosystem. It runs natively across modern **Web Browsers**, **Web Workers**, **Node.js (v18+)**, and **Edge Runtimes** (Cloudflare Workers, Deno, Bun).

> **Disclaimer:** This project is an open-source community contribution and is not an officially supported Google product. Authoritative C++ source and specifications live in [Google Credentio](https://mediaprovenance.googlesource.com/credentio).

---

## Key Features

- **Dual-Layer Architecture**: Use the ergonomic async `CredentioValidator` class or dive into low-level memory allocations with `CredentioWasmBridge`.
- **Isomorphic and Universal**: Operates seamlessly in browser client apps, server-side Node.js pipelines, and edge compute workers without platform-specific dependencies.
- **Strict Cross-Language Schema Parity**: Data models (`ProvenanceReport`, `Manifest`, `Assertion`, `ValidationStatus`) strictly mirror the Python (`credentio`), Go (`credentio-contributions/go`), and Swift (`CredentioKit`) language bindings.
- **C2PA Schema Resilience**: Accommodates C2PA v1 (`claim`) and v2 (`claim.v2`) schemas, dictionary and array manifest representations, X.509 certificate chains, and generator version deduplication.
- **Built-in MIME Sniffing**: Automatically identifies media containers (JPEG, PNG, GIF, WebP, AVIF, HEIC, MP4, MP3, FLAC, WAV, PDF) from binary magic bytes.
- **Explicit Resource Management**: Implements `[Symbol.dispose]()` for modern TypeScript `using` declarations.

---

## Architecture Overview

```
┌────────────────────────────────────────────────────────┐
│                   High-Level API                       │
│  - CredentioValidator (Context-managed / Async)        │
│  - validateBytes(buffer: Uint8Array | ArrayBuffer)     │
│  - validateBlob(blob: Blob)                            │
│  - Strong Data Models (ProvenanceReport, Manifest)     │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│                    Low-Level Bridge                    │
│  - CredentioWasmBridge / Universal Module Loader       │
│  - Memory allocation (_malloc, HEAPU8.set, _free)      │
│  - UTF-8 string conversion (stringToUTF8, UTF8ToString)│
│  - Raw crJSON string parsing & schema normalization    │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│                 Emscripten WASM Engine                 │
│  - credentio.wasm (C++20 Google Credentio runtime)     │
│  - credentio.js (ES6 module glue & factory)            │
└────────────────────────────────────────────────────────┘
```

---

## Installation

Install the package using your preferred package manager (or install directly from GitHub release tarball):

```bash
npm install @ghchinoy/credentio-wasm
# or install from release tarball:
# npm install https://github.com/ghchinoy/credentio-contributions/releases/download/v0.1.5/ghchinoy-credentio-wasm-0.1.5.tgz
```

---

## Quickstart

### 1. In-Browser Drag-and-Drop or File Input

```typescript
import { CredentioValidator } from '@ghchinoy/credentio-wasm';

async function handleFileSelect(file: File) {
  // 1. Initialize validator instance
  const validator = await CredentioValidator.create();

  try {
    // 2. Validate file Blob directly
    const report = await validator.validateBlob(file);

    if (!report.hasCredentials) {
      console.log('No C2PA Content Credentials found in this asset.');
      return;
    }

    // 3. Inspect validation badging and manifest details
    console.log(`Badge status: ${report.badge}`); // 'signed' | 'invalid' | 'unsigned'
    console.log(`Is Verified: ${report.isVerified}`);
    console.log(`Generator: ${report.primaryClaimGenerator}`);
    console.log(`Signing Authority: ${report.primarySignerIssuer}`);

    // 4. Iterate over active manifest assertions
    if (report.activeManifest) {
      for (const assertion of report.activeManifest.assertions) {
        console.log(`Assertion [${assertion.kind}]: ${assertion.label}`);
        if (assertion.summary) {
          console.log(`  Summary: ${assertion.summary}`);
        }
      }
    }
  } finally {
    // 5. Clean up native WASM memory
    validator.close();
  }
}
```

### 2. Node.js (v18+) with Explicit Resource Management (`using`)

```typescript
import * as fs from 'node:fs/promises';
import { CredentioValidator } from '@ghchinoy/credentio-wasm';

async function verifyAsset(filePath: string) {
  const buffer = await fs.readFile(filePath);

  // Uses TypeScript 'using' keyword for automatic resource disposal
  using validator = await CredentioValidator.create();

  const report = await validator.validateBytes(buffer);
  console.log(`Engine: ${report.engineName} (took ${report.elapsedSeconds.toFixed(3)}s)`);
  console.log(`Badge State: ${report.badge}`);
  console.log(`Has Credentials: ${report.hasCredentials}`);
}
```

---

## API Reference

### High-Level API (`CredentioValidator`)

```typescript
class CredentioValidator implements Disposable {
  /** Creates and initializes a new validator instance. */
  static create(options?: ValidatorOptions): Promise<CredentioValidator>;

  /** Validates in-memory byte buffer (Uint8Array or ArrayBuffer). */
  validateBytes(data: Uint8Array | ArrayBuffer, mediaType?: string): Promise<ProvenanceReport>;

  /** Validates a Web standard Blob or File object. */
  validateBlob(blob: Blob, mediaType?: string): Promise<ProvenanceReport>;

  /** True if validator instance is open and active. */
  readonly isOpen: boolean;

  /** Releases WebAssembly heap memory and native validator handles. */
  close(): void;

  /** Explicit resource management hook. */
  [Symbol.dispose](): void;
}
```

#### `ValidatorOptions`

| Option | Type | Description |
|---|---|---|
| `claimSignerTrustPem` | `string` | Optional PEM certificate chain containing trusted root CAs. |
| `tsaTrustPem` | `string` | Optional PEM certificate chain containing trusted TSA roots. |
| `skipTrustChecks` | `boolean` | Skip root certificate anchor checks (defaults to `true` for testing). |
| `locateFile` | `(path: string, prefix: string) => string` | Custom hook to resolve path to `credentio.wasm`. |
| `wasmBinary` | `Uint8Array \| ArrayBuffer` | Pre-fetched WebAssembly binary buffer. |

---

### Core Data Models

#### `ProvenanceReport`

```typescript
interface ProvenanceReport {
  engineId: string;
  engineName: string;
  hasCredentials: boolean;
  elapsedSeconds: number;
  coreSeconds?: number;
  mediaType?: string;
  specVersion?: string;
  activeManifest?: Manifest;
  ingredientManifests: Manifest[];
  rawJson?: string;
  badge: BadgeState; // 'signed' | 'unsigned' | 'invalid'
  isVerified: boolean;
  isInvalid: boolean;
  primaryClaimGenerator?: string;
  primarySignerIssuer?: string;
}
```

#### `Manifest`

```typescript
interface Manifest {
  label: string;
  title?: string;
  format?: string;
  claimGenerator?: string;
  isUpdateManifest: boolean;
  signature?: SignatureInfo;
  assertions: Assertion[];
  validationStatuses: ValidationStatus[];
  overallValidity: BadgeState;
}
```

#### `Assertion`

```typescript
type AssertionKind =
  | 'actions'
  | 'ingredient'
  | 'thumbnail'
  | 'ai_training_mining'
  | 'metadata'
  | 'hash'
  | 'other';

interface Assertion {
  label: string;
  kind: AssertionKind;
  summary?: string;
}
```

---

### Magic Byte Sniffing

The package provides a zero-dependency MIME type sniffer:

```typescript
import { sniffMediaType } from '@ghchinoy/credentio-wasm';

const header = new Uint8Array([0xff, 0xd8, 0xff, 0xe0]);
const mediaType = sniffMediaType(header); // 'image/jpeg'
```

---

## Cross-Language Schema Parity

The TypeScript SDK strictly mirrors data models across all languages in `credentio-contributions`:

| Domain Concept | TypeScript (`@ghchinoy/credentio-wasm`) | Python (`credentio`) | Go (`credentio-contributions/go`) | Swift (`CredentioKit`) |
|---|---|---|---|---|
| **Badge State** | `BadgeState` (`'signed' \| 'unsigned' \| 'invalid'`) | `BadgeState` | `BadgeState` | `CredentialBadgeState` |
| **Severity** | `Severity` (`'info' \| 'warning' \| 'error'`) | `Severity` | `Severity` | `Severity` |
| **Assertion Kind** | `AssertionKind` (7 variants) | `AssertionKind` | `AssertionKind` | `Assertion.Kind` |
| **Report Model** | `ProvenanceReport` | `ProvenanceReport` | `ProvenanceReport` | `ProvenanceReport` |
| **Manifest Model**| `Manifest` | `Manifest` | `Manifest` | `Manifest` |

---

## Building from Source

To compile the native C++20 engine into WebAssembly and build the TypeScript package:

```bash
# 1. Compile native Google Credentio C++20 source into WebAssembly via Emscripten:
make build-wasm

# 2. Install TypeScript build dependencies:
make wasm-install

# 3. Build TypeScript declaration files and bundles:
make wasm-build

# 4. Run Vitest test suite:
make wasm-test
```

---

## License

This package is licensed under the **Apache 2.0 License**. See [LICENSE](LICENSE) for details. Upstream Google Credentio source is licensed under Apache 2.0 (see [LICENSE.credentio](LICENSE.credentio)).
