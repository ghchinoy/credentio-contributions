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

/**
 * Low-level interface exposing Emscripten runtime methods and compiled Credentio C-ABI exports.
 */
export interface CredentioEmscriptenModule {
  _cr_validator_create(
    claimSignerTrustPem: number,
    tsaTrustPem: number,
    skipTrustChecks: number
  ): number;
  _cr_validator_free(validatorPtr: number): void;
  _cr_validate_bytes(
    validatorPtr: number,
    bytesPtr: number,
    count: number,
    mediaTypePtr: number,
    outStatusPtr: number
  ): number;
  _cr_validate_file?(
    validatorPtr: number,
    filePathPtr: number,
    mediaTypePtr: number,
    outStatusPtr: number
  ): number;
  _cr_last_error(validatorPtr: number): number;
  _cr_last_internal_seconds(validatorPtr: number): number;
  _cr_string_free(strPtr: number): void;
  _cr_version(): number;

  _malloc(size: number): number;
  _free(ptr: number): void;

  stringToUTF8(str: string, outPtr: number, maxBytesToWrite: number): void;
  UTF8ToString(ptr: number): string;
  lengthBytesUTF8(str: string): number;
  getValue(ptr: number, type: 'i8' | 'i16' | 'i32' | 'float' | 'double'): number;
  setValue(ptr: number, value: number, type: 'i8' | 'i16' | 'i32' | 'float' | 'double'): void;
  HEAPU8: Uint8Array;
}

/**
 * Options for initializing the Google Credentio WebAssembly module.
 */
export interface WasmInitOptions {
  /** Custom locateFile hook to resolve paths to static assets such as credentio.wasm. */
  locateFile?: (path: string, prefix: string) => string;
  /** Pre-loaded WebAssembly binary buffer (Uint8Array or ArrayBuffer). */
  wasmBinary?: Uint8Array | ArrayBuffer;
  /** Pre-compiled WebAssembly.Module instance. */
  wasmModule?: WebAssembly.Module;
  /** Custom Emscripten module factory if loaded by external bundler. */
  moduleFactory?: (opts?: any) => Promise<CredentioEmscriptenModule>;
}
