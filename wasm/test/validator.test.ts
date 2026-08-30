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

import { describe, expect, it } from 'vitest';
import type { CredentioEmscriptenModule } from '../src/bridge/types.js';
import { CredentioWasmBridge } from '../src/bridge/wasm-bridge.js';
import { CredentioError, CredentioStatusCode } from '../src/errors.js';
import { CredentioValidator } from '../src/validator.js';
import { SAMPLE_CRJSON_V1 } from './fixtures/crjson-samples.js';

/**
 * Creates an in-memory mock Emscripten module simulating Credentio C-ABI behavior.
 */
function createMockEmscriptenModule(options: {
  statusToReturn?: CredentioStatusCode;
  jsonToReturn?: string | null;
  errorMessage?: string;
  coreSeconds?: number;
} = {}): CredentioEmscriptenModule {
  const {
    statusToReturn = CredentioStatusCode.OK,
    jsonToReturn = SAMPLE_CRJSON_V1,
    errorMessage = 'Native error detail',
    coreSeconds = 0.008
  } = options;

  const heap = new Uint8Array(1024 * 1024); // 1 MB heap
  let nextAlloc = 16;
  const stringPool = new Map<number, string>();

  function allocateString(str: string): number {
    const ptr = nextAlloc;
    nextAlloc += Buffer.byteLength(str, 'utf8') + 8;
    stringPool.set(ptr, str);
    return ptr;
  }

  const module: CredentioEmscriptenModule = {
    HEAPU8: heap,
    _malloc(size: number): number {
      const ptr = nextAlloc;
      nextAlloc += size + 8;
      return ptr;
    },
    _free(_ptr: number): void {
      // no-op in mock
    },
    stringToUTF8(str: string, outPtr: number, _maxBytesToWrite: number): void {
      stringPool.set(outPtr, str);
    },
    UTF8ToString(ptr: number): string {
      return stringPool.get(ptr) ?? '';
    },
    lengthBytesUTF8(str: string): number {
      return Buffer.byteLength(str, 'utf8');
    },
    getValue(ptr: number, _type: string): number {
      return (heap[ptr] | (heap[ptr + 1] << 8) | (heap[ptr + 2] << 16) | (heap[ptr + 3] << 24)) >>> 0;
    },
    setValue(ptr: number, value: number, _type: string): void {
      heap[ptr] = value & 0xff;
      heap[ptr + 1] = (value >> 8) & 0xff;
      heap[ptr + 2] = (value >> 16) & 0xff;
      heap[ptr + 3] = (value >> 24) & 0xff;
    },
    _cr_validator_create(_claimPtr: number, _tsaPtr: number, _skipTrust: number): number {
      return 1001; // valid pointer handle
    },
    _cr_validator_free(_valPtr: number): void {
      // no-op
    },
    _cr_validate_bytes(_valPtr, _bytesPtr, _count, _mediaTypePtr, outStatusPtr): number {
      module.setValue(outStatusPtr, statusToReturn, 'i32');
      if (jsonToReturn) {
        return allocateString(jsonToReturn);
      }
      return 0;
    },
    _cr_last_error(_valPtr: number): number {
      return allocateString(errorMessage);
    },
    _cr_last_internal_seconds(_valPtr: number): number {
      return coreSeconds;
    },
    _cr_string_free(strPtr: number): void {
      stringPool.delete(strPtr);
    },
    _cr_version(): number {
      return allocateString('1.4.2-wasm');
    }
  };

  return module;
}

describe('CredentioValidator High-Level API', () => {
  it('instantiates validator, executes validateBytes, and returns ProvenanceReport', async () => {
    const mockModule = createMockEmscriptenModule();
    const validator = await CredentioValidator.create({
      moduleFactory: async () => mockModule
    });

    expect(validator.isOpen).toBe(true);

    const jpegBytes = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);
    const report = await validator.validateBytes(jpegBytes);

    expect(report.hasCredentials).toBe(true);
    expect(report.mediaType).toBe('image/jpeg');
    expect(report.badge).toBe('signed');
    expect(report.isVerified).toBe(true);
    expect(report.primaryClaimGenerator).toBe('Credentio C2PA Tool 1.4.2');
    expect(report.primarySignerIssuer).toBe('Google Authenticity CA');

    validator.close();
    expect(validator.isOpen).toBe(false);
  });

  it('validates Web standard Blob inputs via validateBlob', async () => {
    const mockModule = createMockEmscriptenModule();
    const validator = await CredentioValidator.create({
      moduleFactory: async () => mockModule
    });

    const pngHeader = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    const blob = new Blob([pngHeader], { type: 'image/png' });

    const report = await validator.validateBlob(blob);
    expect(report.hasCredentials).toBe(true);
    expect(report.mediaType).toBe('image/png');

    validator.close();
  });

  it('handles assets without credentials (CR_STATUS_NO_CREDENTIALS)', async () => {
    const mockModule = createMockEmscriptenModule({
      statusToReturn: CredentioStatusCode.NO_CREDENTIALS,
      jsonToReturn: null
    });
    const validator = await CredentioValidator.create({
      moduleFactory: async () => mockModule
    });

    const sampleBytes = new Uint8Array([0xff, 0xd8, 0xff, 0xe0]);
    const report = await validator.validateBytes(sampleBytes);

    expect(report.hasCredentials).toBe(false);
    expect(report.badge).toBe('unsigned');
    expect(report.isVerified).toBe(false);
    expect(report.isInvalid).toBe(false);
    expect(report.activeManifest).toBeUndefined();

    validator.close();
  });

  it('throws CredentioError on empty byte buffers', async () => {
    const mockModule = createMockEmscriptenModule();
    const validator = await CredentioValidator.create({
      moduleFactory: async () => mockModule
    });

    await expect(validator.validateBytes(new Uint8Array([]))).rejects.toThrow(CredentioError);
    await expect(validator.validateBytes(new ArrayBuffer(0))).rejects.toThrow(
      'Input byte buffer cannot be empty.'
    );

    validator.close();
  });

  it('throws CredentioError on native error status', async () => {
    const mockModule = createMockEmscriptenModule({
      statusToReturn: CredentioStatusCode.INTERNAL_ERROR,
      errorMessage: 'C2PA manifest corrupted at box offset 0x40'
    });
    const validator = await CredentioValidator.create({
      moduleFactory: async () => mockModule
    });

    const sampleBytes = new Uint8Array([0x01, 0x02, 0x03, 0x04]);
    await expect(validator.validateBytes(sampleBytes)).rejects.toThrow(
      'Validation failed (status 4): C2PA manifest corrupted at box offset 0x40'
    );

    validator.close();
  });

  it('throws CredentioError when calling closed validator', async () => {
    const mockModule = createMockEmscriptenModule();
    const validator = await CredentioValidator.create({
      moduleFactory: async () => mockModule
    });

    validator.close();
    expect(validator.isOpen).toBe(false);

    await expect(validator.validateBytes(new Uint8Array([1, 2, 3]))).rejects.toThrow(
      'Validator instance has already been closed.'
    );
  });

  it('supports Explicit Resource Management via Symbol.dispose', async () => {
    const mockModule = createMockEmscriptenModule();
    const validator = await CredentioValidator.create({
      moduleFactory: async () => mockModule
    });

    expect(validator.isOpen).toBe(true);
    validator[Symbol.dispose]();
    expect(validator.isOpen).toBe(false);
  });
});

describe('CredentioWasmBridge Low-Level API', () => {
  it('reports C-ABI version and executes direct validateBytes', () => {
    const mockModule = createMockEmscriptenModule();
    const bridge = new CredentioWasmBridge(mockModule, undefined, undefined, true);

    expect(bridge.isOpen).toBe(true);
    expect(bridge.getVersion()).toBe('1.4.2-wasm');

    const result = bridge.validateBytes(new Uint8Array([0xff, 0xd8, 0xff]), 'image/jpeg');
    expect(result.status).toBe(CredentioStatusCode.OK);
    expect(result.rawJson).toBe(SAMPLE_CRJSON_V1);
    expect(result.coreSeconds).toBe(0.008);

    bridge.close();
    expect(bridge.isOpen).toBe(false);
  });
});
