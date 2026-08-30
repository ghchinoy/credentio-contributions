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

import { CredentioError, CredentioStatusCode } from '../errors.js';
import type { CredentioEmscriptenModule } from './types.js';

/**
 * Raw validation result returned by low-level C-ABI invocation.
 */
export interface RawValidationResult {
  /** Return status code from native engine. */
  status: CredentioStatusCode;
  /** Raw crJSON string, or null if no manifest was generated. */
  rawJson: string | null;
  /** Native engine core processing time in seconds. */
  coreSeconds: number;
  /** Detailed error message if status is not OK. */
  errorMessage?: string;
}

/**
 * Low-level WebAssembly bridge managing memory allocations, C pointer marshalling,
 * and direct invocations of the Credentio C-ABI exports.
 */
export class CredentioWasmBridge {
  private validatorPtr: number = 0;

  constructor(
    private readonly module: CredentioEmscriptenModule,
    claimSignerTrustPem?: string,
    tsaTrustPem?: string,
    skipTrustChecks: boolean = true
  ) {
    let claimPtr = 0;
    let tsaPtr = 0;

    if (claimSignerTrustPem && claimSignerTrustPem.length > 0) {
      const len = module.lengthBytesUTF8(claimSignerTrustPem) + 1;
      claimPtr = module._malloc(len);
      module.stringToUTF8(claimSignerTrustPem, claimPtr, len);
    }

    if (tsaTrustPem && tsaTrustPem.length > 0) {
      const len = module.lengthBytesUTF8(tsaTrustPem) + 1;
      tsaPtr = module._malloc(len);
      module.stringToUTF8(tsaTrustPem, tsaPtr, len);
    }

    try {
      this.validatorPtr = module._cr_validator_create(
        claimPtr,
        tsaPtr,
        skipTrustChecks ? 1 : 0
      );
      if (!this.validatorPtr) {
        throw new CredentioError('Failed to allocate native Credentio validator handle.');
      }
    } finally {
      if (claimPtr) module._free(claimPtr);
      if (tsaPtr) module._free(tsaPtr);
    }
  }

  /**
   * Validates in-memory binary asset bytes via native C-ABI.
   *
   * @param bytes Uint8Array containing media asset data.
   * @param mediaType Optional IANA media type string.
   * @returns Raw validation status, crJSON string, and core execution timing.
   */
  public validateBytes(bytes: Uint8Array, mediaType?: string): RawValidationResult {
    if (!this.validatorPtr) {
      throw new CredentioError('Validator instance has already been closed.');
    }

    const count = bytes.byteLength;
    if (count === 0) {
      throw new CredentioError('Input byte buffer cannot be empty.');
    }

    const bytesPtr = this.module._malloc(count);
    this.module.HEAPU8.set(bytes, bytesPtr);

    let mediaTypePtr = 0;
    if (mediaType && mediaType.length > 0) {
      const len = this.module.lengthBytesUTF8(mediaType) + 1;
      mediaTypePtr = this.module._malloc(len);
      this.module.stringToUTF8(mediaType, mediaTypePtr, len);
    }

    const statusPtr = this.module._malloc(4);
    this.module.setValue(statusPtr, 0, 'i32');

    let jsonPtr = 0;
    let status: CredentioStatusCode = CredentioStatusCode.OK;
    let rawJson: string | null = null;
    let coreSeconds = 0;
    let errorMessage: string | undefined;

    try {
      jsonPtr = this.module._cr_validate_bytes(
        this.validatorPtr,
        bytesPtr,
        count,
        mediaTypePtr,
        statusPtr
      );
      status = this.module.getValue(statusPtr, 'i32') as CredentioStatusCode;
      coreSeconds = this.module._cr_last_internal_seconds(this.validatorPtr);

      if (jsonPtr !== 0) {
        rawJson = this.module.UTF8ToString(jsonPtr);
      }

      if (status !== CredentioStatusCode.OK && status !== CredentioStatusCode.NO_CREDENTIALS) {
        const errPtr = this.module._cr_last_error(this.validatorPtr);
        errorMessage = errPtr ? this.module.UTF8ToString(errPtr) : 'Unknown native error';
      }
    } finally {
      if (jsonPtr !== 0) {
        this.module._cr_string_free(jsonPtr);
      }
      this.module._free(bytesPtr);
      this.module._free(statusPtr);
      if (mediaTypePtr !== 0) {
        this.module._free(mediaTypePtr);
      }
    }

    return { status, rawJson, coreSeconds, errorMessage };
  }

  /**
   * Retrieves the version string of the underlying Google Credentio C-ABI bridge.
   */
  public getVersion(): string {
    const ptr = this.module._cr_version();
    return ptr ? this.module.UTF8ToString(ptr) : 'unknown';
  }

  /**
   * Releases native C-ABI validator resources.
   */
  public close(): void {
    if (this.validatorPtr) {
      this.module._cr_validator_free(this.validatorPtr);
      this.validatorPtr = 0;
    }
  }

  /**
   * Returns true if the native validator instance is active and not closed.
   */
  public get isOpen(): boolean {
    return this.validatorPtr !== 0;
  }
}
