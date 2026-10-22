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
import type { CredentioEmscriptenModule, WasmInitOptions } from './bridge/types.js';
import { CredentioError, CredentioStatusCode } from './errors.js';
import { sniffMediaType } from './sniff.js';

/**
 * Options for configuring a CredentioSigner instance.
 */
export interface SignerOptions extends WasmInitOptions {
  /** Required PEM-encoded EC P-256 private key (PKCS#8) for signing claims. */
  claimSignerKeyPem: string;
  /** Required PEM-encoded X.509 certificate chain (leaf first) for the claim signer. */
  claimSignerCertPem: string;
  /** Optional PEM-encoded EC P-256 private key for RFC 3161 timestamping. */
  tsaKeyPem?: string;
  /** Optional PEM-encoded X.509 certificate for RFC 3161 timestamping. */
  tsaCertPem?: string;
  /** Claim generator software name (defaults to `'Credentio (WebAssembly)'`). */
  generatorName?: string;
  /** Claim generator software version (defaults to `'0.2.1'`). */
  generatorVersion?: string;
}

/**
 * Per-asset parameters when embedding and signing C2PA Content Credentials.
 */
export interface SignBytesParams {
  /** Optional IANA media type (e.g. `'image/png'`). If omitted, sniffed from magic bytes. */
  mediaType?: string;
  /** Optional IPTC digitalSourceType URI (e.g. `'http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture'`). */
  digitalSourceType?: string;
  /** Optional custom JSON assertions object mapping assertion labels to JSON payloads. */
  customAssertions?: Record<string, unknown>;
}

/**
 * Result returned by in-memory WebAssembly C2PA asset signing.
 */
export interface SignResult {
  /** Signed media asset bytes with embedded C2PA Content Credentials. */
  signedBytes: Uint8Array;
  /** Total byte size of the signed asset. */
  byteSize: number;
  /** Resolved IANA media type of the signed asset. */
  mediaType?: string;
  /** Total wall-clock signing time in seconds. */
  elapsedSeconds: number;
  /** Native C++ engine core signing time in seconds. */
  coreSeconds: number;
}

/**
 * High-level, isomorphic C2PA Content Credentials signer for Google Credentio.
 *
 * Enables 100% client-side C2PA manifest generation and signing in Web Browsers,
 * Web Workers, Node.js, and Edge Runtimes without uploading media or keys to a server.
 */
export class CredentioSigner {
  private signerPtr: number = 0;

  private constructor(
    private readonly module: CredentioEmscriptenModule,
    signerPtr: number
  ) {
    this.signerPtr = signerPtr;
  }

  /**
   * Initializes a new CredentioSigner instance from PEM-encoded EC P-256 credentials.
   */
  public static async create(options: SignerOptions): Promise<CredentioSigner> {
    if (!options.claimSignerKeyPem || !options.claimSignerCertPem) {
      throw new CredentioError(
        'claimSignerKeyPem and claimSignerCertPem are required.',
        CredentioStatusCode.INVALID_ARGUMENT
      );
    }

    const wasmModule = await loadCredentioWasm(options);
    if (!wasmModule._cr_signer_create) {
      throw new CredentioError(
        'Loaded WebAssembly binary does not export _cr_signer_create (rebuild with make build-wasm).'
      );
    }

    const allocCString = (s?: string): number => {
      if (!s || s.length === 0) return 0;
      const len = wasmModule.lengthBytesUTF8(s) + 1;
      const ptr = wasmModule._malloc(len);
      wasmModule.stringToUTF8(s, ptr, len);
      return ptr;
    };

    const keyPtr = allocCString(options.claimSignerKeyPem);
    const certPtr = allocCString(options.claimSignerCertPem);
    const tsaKeyPtr = allocCString(options.tsaKeyPem);
    const tsaCertPtr = allocCString(options.tsaCertPem);
    const genNamePtr = allocCString(options.generatorName ?? 'Credentio (WebAssembly)');
    const genVerPtr = allocCString(options.generatorVersion ?? '0.2.1');

    try {
      const signerPtr = wasmModule._cr_signer_create(
        keyPtr,
        certPtr,
        tsaKeyPtr,
        tsaCertPtr,
        genNamePtr,
        genVerPtr
      );
      if (!signerPtr) {
        throw new CredentioError(
          'Failed to initialize native Credentio signer (verify EC P-256 PKCS#8 key and certificate chain).',
          CredentioStatusCode.INVALID_ARGUMENT
        );
      }
      return new CredentioSigner(wasmModule, signerPtr);
    } finally {
      if (keyPtr) wasmModule._free(keyPtr);
      if (certPtr) wasmModule._free(certPtr);
      if (tsaKeyPtr) wasmModule._free(tsaKeyPtr);
      if (tsaCertPtr) wasmModule._free(tsaCertPtr);
      if (genNamePtr) wasmModule._free(genNamePtr);
      if (genVerPtr) wasmModule._free(genVerPtr);
    }
  }

  /**
   * Embeds and signs a C2PA manifest into an in-memory byte buffer (`Uint8Array` or `ArrayBuffer`).
   */
  public async signBytes(
    data: Uint8Array | ArrayBuffer,
    params: SignBytesParams = {}
  ): Promise<SignResult> {
    if (!this.signerPtr) {
      throw new CredentioError('Signer instance has already been closed.');
    }
    if (!this.module._cr_sign_bytes) {
      throw new CredentioError('Loaded WebAssembly binary does not export _cr_sign_bytes.');
    }

    const uint8 = data instanceof Uint8Array ? data : new Uint8Array(data);
    if (uint8.byteLength === 0) {
      throw new CredentioError(
        'Input byte buffer cannot be empty.',
        CredentioStatusCode.INVALID_ARGUMENT
      );
    }

    const resolvedMediaType = params.mediaType || sniffMediaType(uint8);

    const allocCString = (s?: string): number => {
      if (!s || s.length === 0) return 0;
      const len = this.module.lengthBytesUTF8(s) + 1;
      const ptr = this.module._malloc(len);
      this.module.stringToUTF8(s, ptr, len);
      return ptr;
    };

    const bytesPtr = this.module._malloc(uint8.byteLength);
    this.module.HEAPU8.set(uint8, bytesPtr);

    const mediaTypePtr = allocCString(resolvedMediaType);
    const dstPtr = allocCString(params.digitalSourceType);
    const assertionsJson = params.customAssertions
      ? JSON.stringify(params.customAssertions)
      : undefined;
    const assertionsPtr = allocCString(assertionsJson);

    const outSizePtr = this.module._malloc(4);
    const outStatusPtr = this.module._malloc(4);
    this.module.setValue(outSizePtr, 0, 'i32');
    this.module.setValue(outStatusPtr, 0, 'i32');

    let signedPtr = 0;
    try {
      const startTime = typeof performance !== 'undefined' ? performance.now() : Date.now();
      signedPtr = this.module._cr_sign_bytes(
        this.signerPtr,
        bytesPtr,
        uint8.byteLength,
        mediaTypePtr,
        dstPtr,
        assertionsPtr,
        outSizePtr,
        outStatusPtr
      );
      const elapsedSeconds =
        ((typeof performance !== 'undefined' ? performance.now() : Date.now()) - startTime) / 1000;
      const coreSeconds = this.module._cr_signer_last_internal_seconds
        ? this.module._cr_signer_last_internal_seconds(this.signerPtr)
        : 0;
      const status = this.module.getValue(outStatusPtr, 'i32') as CredentioStatusCode;
      const outSize = this.module.getValue(outSizePtr, 'i32');

      if (!signedPtr || status !== CredentioStatusCode.OK || outSize <= 0) {
        const errPtr = this.module._cr_signer_last_error
          ? this.module._cr_signer_last_error(this.signerPtr)
          : 0;
        const errMsg = errPtr ? this.module.UTF8ToString(errPtr) : 'Unknown signing error';
        throw new CredentioError(`Signing failed (status ${status}): ${errMsg}`, status);
      }

      const signedBytes = new Uint8Array(outSize);
      signedBytes.set(this.module.HEAPU8.subarray(signedPtr, signedPtr + outSize));

      return {
        signedBytes,
        byteSize: outSize,
        mediaType: resolvedMediaType,
        elapsedSeconds,
        coreSeconds
      };
    } finally {
      if (signedPtr) {
        if (this.module._cr_bytes_free) {
          this.module._cr_bytes_free(signedPtr);
        } else {
          this.module._free(signedPtr);
        }
      }
      this.module._free(bytesPtr);
      this.module._free(outSizePtr);
      this.module._free(outStatusPtr);
      if (mediaTypePtr) this.module._free(mediaTypePtr);
      if (dstPtr) this.module._free(dstPtr);
      if (assertionsPtr) this.module._free(assertionsPtr);
    }
  }

  /**
   * Embeds and signs a C2PA manifest into a Web standard Blob or File and returns a signed Blob.
   */
  public async signBlob(blob: Blob, params: SignBytesParams = {}): Promise<Blob> {
    const arrayBuffer = await blob.arrayBuffer();
    const res = await this.signBytes(arrayBuffer, {
      ...params,
      mediaType: params.mediaType || (blob.type ? blob.type : undefined)
    });
    return new Blob([res.signedBytes as unknown as BlobPart], { type: res.mediaType || blob.type });
  }

  /**
   * Returns true if the signer instance is active and has not been closed.
   */
  public get isOpen(): boolean {
    return this.signerPtr !== 0;
  }

  /**
   * Releases all underlying WebAssembly memory and native signer handles.
   */
  public close(): void {
    if (this.signerPtr) {
      if (this.module._cr_signer_free) {
        this.module._cr_signer_free(this.signerPtr);
      }
      this.signerPtr = 0;
    }
  }

  /**
   * Explicit Resource Management hook for TypeScript `using` declarations.
   */
  public [Symbol.dispose](): void {
    this.close();
  }
}
