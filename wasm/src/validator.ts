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

import { loadCredentioWasm } from './bridge/loader.js';
import type { WasmInitOptions } from './bridge/types.js';
import { CredentioWasmBridge } from './bridge/wasm-bridge.js';
import { CredentioError, CredentioStatusCode } from './errors.js';
import { createProvenanceReport, type ProvenanceReport } from './models.js';
import { parseCrJSON } from './parser.js';
import { sniffMediaType } from './sniff.js';

/**
 * Options for configuring a CredentioValidator instance.
 */
export interface ValidatorOptions extends WasmInitOptions {
  /** Optional PEM string containing trusted claim signer certificate authorities. */
  claimSignerTrustPem?: string;
  /** Optional PEM string containing trusted Time Stamping Authority (TSA) certificates. */
  tsaTrustPem?: string;
  /**
   * Skip cryptographic trust root verification.
   * Defaults to `true` for development, browser validation, and test workflows.
   */
  skipTrustChecks?: boolean;
}

/**
 * High-level, isomorphic C2PA content credentials validator for Google Credentio.
 *
 * Supports in-memory byte buffers (`Uint8Array`, `ArrayBuffer`) and Web standard `Blob`/`File`
 * objects across Web Browsers, Web Workers, Node.js (v18+), and Edge Runtimes.
 *
 * Implements Explicit Resource Management (`using` statement / `[Symbol.dispose]()`).
 */
export class CredentioValidator {
  private bridge: CredentioWasmBridge | null = null;

  private constructor(bridge: CredentioWasmBridge) {
    this.bridge = bridge;
  }

  /**
   * Initializes a new CredentioValidator instance.
   *
   * @param options Optional initialization and trust configuration options.
   * @returns Configured CredentioValidator ready for validation requests.
   */
  public static async create(options: ValidatorOptions = {}): Promise<CredentioValidator> {
    const wasmModule = await loadCredentioWasm(options);
    const bridge = new CredentioWasmBridge(
      wasmModule,
      options.claimSignerTrustPem,
      options.tsaTrustPem,
      options.skipTrustChecks ?? true
    );
    return new CredentioValidator(bridge);
  }

  /**
   * Validates in-memory asset bytes against the C2PA specification and returns a typed ProvenanceReport.
   *
   * @param data Binary buffer (`Uint8Array` or `ArrayBuffer`) containing media content.
   * @param mediaType Optional IANA media type (e.g. `'image/jpeg'`). If omitted, sniffed from header.
   * @returns Typed ProvenanceReport containing active/ingredient manifests and badging.
   */
  public async validateBytes(
    data: Uint8Array | ArrayBuffer,
    mediaType?: string
  ): Promise<ProvenanceReport> {
    if (!this.bridge) {
      throw new CredentioError('Validator instance has already been closed.');
    }

    const uint8 = data instanceof Uint8Array ? data : new Uint8Array(data);
    if (uint8.byteLength === 0) {
      throw new CredentioError(
        'Input byte buffer cannot be empty.',
        CredentioStatusCode.INVALID_ARGUMENT
      );
    }

    const resolvedMediaType = mediaType || sniffMediaType(uint8);

    const startTime = typeof performance !== 'undefined' ? performance.now() : Date.now();
    const result = this.bridge.validateBytes(uint8, resolvedMediaType);
    const elapsedSeconds =
      ((typeof performance !== 'undefined' ? performance.now() : Date.now()) - startTime) / 1000;

    if (result.status === CredentioStatusCode.NO_CREDENTIALS || !result.rawJson) {
      return createProvenanceReport({
        engineId: 'credentio-wasm',
        engineName: 'Credentio (WebAssembly)',
        hasCredentials: false,
        elapsedSeconds,
        coreSeconds: result.coreSeconds,
        mediaType: resolvedMediaType,
        rawJson: result.rawJson ?? undefined
      });
    }

    if (result.status !== CredentioStatusCode.OK) {
      throw new CredentioError(
        `Validation failed (status ${result.status}): ${result.errorMessage || 'Unknown error'}`,
        result.status
      );
    }

    return parseCrJSON(
      result.rawJson,
      resolvedMediaType,
      elapsedSeconds,
      result.coreSeconds,
      'credentio-wasm',
      'Credentio (WebAssembly)'
    );
  }

  /**
   * Validates a Web standard Blob or File (e.g. from `<input type="file">` or drag-and-drop events).
   *
   * @param blob Blob or File object to validate.
   * @param mediaType Optional explicit media type override. Defaults to `blob.type`.
   * @returns Typed ProvenanceReport.
   */
  public async validateBlob(blob: Blob, mediaType?: string): Promise<ProvenanceReport> {
    const arrayBuffer = await blob.arrayBuffer();
    return this.validateBytes(arrayBuffer, mediaType || (blob.type ? blob.type : undefined));
  }

  /**
   * Returns true if the validator is active and has not been closed.
   */
  public get isOpen(): boolean {
    return this.bridge?.isOpen ?? false;
  }

  /**
   * Releases all underlying WebAssembly memory allocations and native validator handles.
   */
  public close(): void {
    if (this.bridge) {
      this.bridge.close();
      this.bridge = null;
    }
  }

  /**
   * Explicit Resource Management hook for TypeScript `using` declarations.
   */
  public [Symbol.dispose](): void {
    this.close();
  }
}
