// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Error types
export { CredentioError, CredentioStatusCode } from './errors.js';

// Domain models & functions
export {
  type Assertion,
  type AssertionKind,
  type BadgeState,
  type CreateProvenanceReportParams,
  createProvenanceReport,
  classifyAssertion,
  getManifestValidity,
  type Manifest,
  type ProvenanceReport,
  type Severity,
  type SignatureInfo,
  type ValidationStatus
} from './models.js';

// Media type sniffing
export { sniffMediaType } from './sniff.js';

// crJSON Parser
export { parseCrJSON } from './parser.js';

// Low-level WebAssembly bridge
export {
  type CredentioEmscriptenModule,
  type WasmInitOptions
} from './bridge/types.js';
export { loadCredentioWasm, resetCachedWasmModule } from './bridge/loader.js';
export {
  CredentioWasmBridge,
  type RawValidationResult
} from './bridge/wasm-bridge.js';

// High-level Validator API
export {
  CredentioValidator,
  type ValidatorOptions
} from './validator.js';
