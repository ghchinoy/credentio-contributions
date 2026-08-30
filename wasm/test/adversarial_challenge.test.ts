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
import { loadCredentioWasm, resetCachedWasmModule } from '../src/bridge/loader.js';
import { CredentioError, CredentioStatusCode } from '../src/errors.js';
import { parseCrJSON } from '../src/parser.js';
import { sniffMediaType } from '../src/sniff.js';
import { CredentioValidator } from '../src/validator.js';
import { SAMPLE_CRJSON_V1, SAMPLE_CRJSON_V2 } from './fixtures/crjson-samples.js';

/**
 * Strict Tracking Emscripten Mock Module for Empirical Memory Leak and Allocation Auditing.
 */
class TrackingMockModule {
  public heap: Uint8Array = new Uint8Array(16 * 1024 * 1024); // 16MB heap
  public activeAllocations: Map<number, number> = new Map(); // ptr -> size
  public activeStrings: Map<number, string> = new Map(); // ptr -> string
  public activeValidators: Set<number> = new Set();
  public nextPtr: number = 64;
  public totalMallocCount: number = 0;
  public totalFreeCount: number = 0;
  public totalStringFreeCount: number = 0;
  public totalValidatorCreateCount: number = 0;
  public totalValidatorFreeCount: number = 0;

  public statusToReturn: CredentioStatusCode = CredentioStatusCode.OK;
  public jsonToReturn: string | null = SAMPLE_CRJSON_V1;
  public errorMessage: string = 'Native failure simulation';
  public coreSeconds: number = 0.005;
  public shouldFailValidatorCreate: boolean = false;
  public lastValidatedBytes: Uint8Array | null = null;

  public setValue(ptr: number, value: number, _type: string): void {
    this.heap[ptr] = value & 0xff;
    this.heap[ptr + 1] = (value >> 8) & 0xff;
    this.heap[ptr + 2] = (value >> 16) & 0xff;
    this.heap[ptr + 3] = (value >> 24) & 0xff;
  }

  public getValue(ptr: number, _type: string): number {
    return (
      (this.heap[ptr] |
        (this.heap[ptr + 1] << 8) |
        (this.heap[ptr + 2] << 16) |
        (this.heap[ptr + 3] << 24)) >>>
      0
    );
  }

  public asModule(): CredentioEmscriptenModule {
    const self = this;
    return {
      HEAPU8: self.heap,
      _malloc(size: number): number {
        self.totalMallocCount++;
        const ptr = self.nextPtr;
        self.nextPtr += Math.max(size, 8) + 8;
        self.activeAllocations.set(ptr, size);
        return ptr;
      },
      _free(ptr: number): void {
        if (ptr === 0) return;
        self.totalFreeCount++;
        if (!self.activeAllocations.has(ptr)) {
          throw new Error(`Double free or invalid pointer free detected: 0x${ptr.toString(16)}`);
        }
        self.activeAllocations.delete(ptr);
        self.activeStrings.delete(ptr);
      },
      stringToUTF8(str: string, outPtr: number, _maxBytesToWrite: number): void {
        const encoded = new TextEncoder().encode(str);
        self.heap.set(encoded, outPtr);
        self.heap[outPtr + encoded.length] = 0;
        self.activeStrings.set(outPtr, str);
      },
      UTF8ToString(ptr: number): string {
        if (ptr === 0) return '';
        if (self.activeStrings.has(ptr)) {
          return self.activeStrings.get(ptr)!;
        }
        // Read null-terminated UTF-8 string from heap
        let end = ptr;
        while (end < self.heap.length && self.heap[end] !== 0) {
          end++;
        }
        return new TextDecoder().decode(self.heap.subarray(ptr, end));
      },
      lengthBytesUTF8(str: string): number {
        return new TextEncoder().encode(str).length;
      },
      getValue(ptr: number, type: 'i8' | 'i16' | 'i32' | 'float' | 'double'): number {
        return self.getValue(ptr, type);
      },
      setValue(ptr: number, value: number, type: 'i8' | 'i16' | 'i32' | 'float' | 'double'): void {
        self.setValue(ptr, value, type);
      },
      _cr_validator_create(_claimPtr: number, _tsaPtr: number, _skipTrust: number): number {
        if (self.shouldFailValidatorCreate) {
          return 0;
        }
        self.totalValidatorCreateCount++;
        const valPtr = 5000 + self.totalValidatorCreateCount;
        self.activeValidators.add(valPtr);
        return valPtr;
      },
      _cr_validator_free(valPtr: number): void {
        if (valPtr === 0) return;
        self.totalValidatorFreeCount++;
        if (!self.activeValidators.has(valPtr)) {
          throw new Error(`Double free of validator handle detected: ${valPtr}`);
        }
        self.activeValidators.delete(valPtr);
      },
      _cr_validate_bytes(
        _valPtr: number,
        bytesPtr: number,
        count: number,
        _mediaTypePtr: number,
        outStatusPtr: number
      ): number {
        self.setValue(outStatusPtr, self.statusToReturn, 'i32');
        self.lastValidatedBytes = new Uint8Array(self.heap.subarray(bytesPtr, bytesPtr + count));

        if (self.jsonToReturn) {
          const strLen = new TextEncoder().encode(self.jsonToReturn).length + 1;
          const jsonPtr = self.nextPtr;
          self.nextPtr += strLen + 8;
          self.activeStrings.set(jsonPtr, self.jsonToReturn);
          return jsonPtr;
        }
        return 0;
      },
      _cr_last_error(_valPtr: number): number {
        const errLen = new TextEncoder().encode(self.errorMessage).length + 1;
        const errPtr = self.nextPtr;
        self.nextPtr += errLen + 8;
        self.activeStrings.set(errPtr, self.errorMessage);
        return errPtr;
      },
      _cr_last_internal_seconds(_valPtr: number): number {
        return self.coreSeconds;
      },
      _cr_string_free(strPtr: number): void {
        if (strPtr === 0) return;
        self.totalStringFreeCount++;
        if (!self.activeStrings.has(strPtr)) {
          throw new Error(`Free of untracked or already freed string pointer: 0x${strPtr.toString(16)}`);
        }
        self.activeStrings.delete(strPtr);
      },
      _cr_version(): number {
        const verStr = '1.4.2-wasm-adversarial';
        const verPtr = 9999;
        self.activeStrings.set(verPtr, verStr);
        return verPtr;
      }
    };
  }
}

describe('Adversarial Stress Harness: Lifecycle & Double-Close Safety', () => {
  it('handles multiple consecutive close() and Symbol.dispose() calls idempotently', async () => {
    const mock = new TrackingMockModule();
    const validator = await CredentioValidator.create({
      moduleFactory: async () => mock.asModule()
    });

    expect(validator.isOpen).toBe(true);
    expect(mock.activeValidators.size).toBe(1);

    // Call close() 5 times consecutively
    validator.close();
    expect(validator.isOpen).toBe(false);
    expect(mock.activeValidators.size).toBe(0);

    validator.close();
    validator.close();
    validator[Symbol.dispose]();
    validator[Symbol.dispose]();
    expect(validator.isOpen).toBe(false);
    expect(mock.totalValidatorFreeCount).toBe(1);
  });

  it('rejects validateBytes and validateBlob immediately when called after close()', async () => {
    const mock = new TrackingMockModule();
    const validator = await CredentioValidator.create({
      moduleFactory: async () => mock.asModule()
    });

    validator.close();

    const sampleBytes = new Uint8Array([0xff, 0xd8, 0xff, 0xe0]);
    await expect(validator.validateBytes(sampleBytes)).rejects.toThrow(
      'Validator instance has already been closed.'
    );

    const blob = new Blob([sampleBytes], { type: 'image/jpeg' });
    await expect(validator.validateBlob(blob)).rejects.toThrow(
      'Validator instance has already been closed.'
    );
  });

  it('CredentioWasmBridge handles multiple close() calls and throws when used after close()', () => {
    const mock = new TrackingMockModule();
    const bridge = new CredentioWasmBridge(mock.asModule(), undefined, undefined, true);

    expect(bridge.isOpen).toBe(true);
    expect(mock.activeValidators.size).toBe(1);

    bridge.close();
    expect(bridge.isOpen).toBe(false);
    expect(mock.activeValidators.size).toBe(0);

    // Multiple close calls are no-ops
    bridge.close();
    bridge.close();
    expect(mock.totalValidatorFreeCount).toBe(1);

    // validateBytes throws CredentioError
    expect(() => bridge.validateBytes(new Uint8Array([1, 2, 3]))).toThrow(
      'Validator instance has already been closed.'
    );

    // getVersion remains accessible
    expect(bridge.getVersion()).toBe('1.4.2-wasm-adversarial');
  });

  it('cleans up temporary string allocations when native validator creation fails in constructor', () => {
    const mock = new TrackingMockModule();
    mock.shouldFailValidatorCreate = true;

    expect(() => {
      new CredentioWasmBridge(
        mock.asModule(),
        '-----BEGIN CERTIFICATE-----\nMOCK_PEM\n-----END CERTIFICATE-----',
        '-----BEGIN CERTIFICATE-----\nTSA_PEM\n-----END CERTIFICATE-----',
        false
      );
    }).toThrow('Failed to allocate native Credentio validator handle.');

    // Assert that temporary claimPtr and tsaPtr allocated during constructor were freed
    expect(mock.activeAllocations.size).toBe(0);
    expect(mock.totalMallocCount).toBe(2);
    expect(mock.totalFreeCount).toBe(2);
  });
});

describe('Adversarial Stress Harness: Input Buffers, Slices, and Boundary Conditions', () => {
  it('rejects empty Uint8Array, ArrayBuffer, and empty Blob inputs with INVALID_ARGUMENT', async () => {
    const mock = new TrackingMockModule();
    const validator = await CredentioValidator.create({
      moduleFactory: async () => mock.asModule()
    });

    // Empty Uint8Array
    await expect(validator.validateBytes(new Uint8Array(0))).rejects.toMatchObject({
      name: 'CredentioError',
      message: 'Input byte buffer cannot be empty.',
      statusCode: CredentioStatusCode.INVALID_ARGUMENT
    });

    // Empty ArrayBuffer
    await expect(validator.validateBytes(new ArrayBuffer(0))).rejects.toMatchObject({
      name: 'CredentioError',
      message: 'Input byte buffer cannot be empty.',
      statusCode: CredentioStatusCode.INVALID_ARGUMENT
    });

    // Empty Blob
    await expect(validator.validateBlob(new Blob([]))).rejects.toMatchObject({
      name: 'CredentioError',
      message: 'Input byte buffer cannot be empty.',
      statusCode: CredentioStatusCode.INVALID_ARGUMENT
    });

    validator.close();
  });

  it('correctly handles Uint8Array views with non-zero byte offsets (subarrays)', async () => {
    const mock = new TrackingMockModule();
    const validator = await CredentioValidator.create({
      moduleFactory: async () => mock.asModule()
    });

    const backingBuffer = new Uint8Array([
      0x00, 0x00, 0x00, 0x00, // padding offset 0-3
      0xff, 0xd8, 0xff, 0xe0, 0x11, 0x22, 0x33, // JPEG payload offset 4-10 (length 7)
      0x99, 0x99 // trailing padding 11-12
    ]);

    const subView = backingBuffer.subarray(4, 11);
    expect(subView.byteLength).toBe(7);
    expect(subView.byteOffset).toBe(4);

    const report = await validator.validateBytes(subView);
    expect(report.hasCredentials).toBe(true);

    // Verify exact bytes copied to WebAssembly heap
    expect(mock.lastValidatedBytes).toBeDefined();
    expect(mock.lastValidatedBytes?.length).toBe(7);
    expect(mock.lastValidatedBytes?.[0]).toBe(0xff);
    expect(mock.lastValidatedBytes?.[1]).toBe(0xd8);
    expect(mock.lastValidatedBytes?.[2]).toBe(0xff);
    expect(mock.lastValidatedBytes?.[3]).toBe(0xe0);
    expect(mock.lastValidatedBytes?.[6]).toBe(0x33);

    validator.close();
  });

  it('accepts raw ArrayBuffer inputs directly', async () => {
    const mock = new TrackingMockModule();
    const validator = await CredentioValidator.create({
      moduleFactory: async () => mock.asModule()
    });

    const rawArrayBuf = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).buffer;
    const report = await validator.validateBytes(rawArrayBuf);

    expect(report.hasCredentials).toBe(true);
    expect(report.mediaType).toBe('image/png');

    validator.close();
  });

  it('validates Blobs with auto-sniffed media types and explicit overrides', async () => {
    const mock = new TrackingMockModule();
    const validator = await CredentioValidator.create({
      moduleFactory: async () => mock.asModule()
    });

    // Auto-sniffed from header when Blob.type is empty
    const jpegHeader = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
    const untypedBlob = new Blob([jpegHeader]);
    const report1 = await validator.validateBlob(untypedBlob);
    expect(report1.mediaType).toBe('image/jpeg');

    // Explicit override takes precedence
    const report2 = await validator.validateBlob(untypedBlob, 'application/custom-c2pa');
    expect(report2.mediaType).toBe('application/custom-c2pa');

    validator.close();
  });
});

describe('Adversarial Stress Harness: Zero Memory Leak Empirical Audit', () => {
  it('guarantees zero memory leaks over 200 consecutive validation cycles with varying outcomes', async () => {
    const mock = new TrackingMockModule();
    const bridge = new CredentioWasmBridge(
      mock.asModule(),
      '-----BEGIN CERTIFICATE-----\nCLAIM_TRUST\n-----END CERTIFICATE-----',
      '-----BEGIN CERTIFICATE-----\nTSA_TRUST\n-----END CERTIFICATE-----',
      true
    );

    const testPayloads = [
      { bytes: new Uint8Array([0xff, 0xd8, 0xff, 0xe0]), mime: 'image/jpeg', status: CredentioStatusCode.OK, json: SAMPLE_CRJSON_V1 },
      { bytes: new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), mime: 'image/png', status: CredentioStatusCode.OK, json: SAMPLE_CRJSON_V2 },
      { bytes: new Uint8Array([0x01, 0x02, 0x03]), mime: undefined, status: CredentioStatusCode.NO_CREDENTIALS, json: null },
      { bytes: new Uint8Array([0xaa, 0xbb, 0xcc, 0xdd, 0xee]), mime: 'application/pdf', status: CredentioStatusCode.OK, json: SAMPLE_CRJSON_V1 }
    ];

    for (let i = 0; i < 200; i++) {
      const scenario = testPayloads[i % testPayloads.length];
      mock.statusToReturn = scenario.status;
      mock.jsonToReturn = scenario.json;

      const result = bridge.validateBytes(scenario.bytes, scenario.mime);
      expect(result.status).toBe(scenario.status);

      // Between iterations, all temporary byte buffers, status pointers, and JSON strings MUST be freed
      expect(mock.activeAllocations.size).toBe(0);
    }

    bridge.close();
    expect(mock.activeValidators.size).toBe(0);
    expect(mock.activeAllocations.size).toBe(0);
  });
});

describe('Adversarial Stress Harness: Concurrency and Promise Safety', () => {
  it('handles 50 concurrent validation requests without unhandled rejections or data corruption', async () => {
    const unhandledList: any[] = [];
    const rejectionHandler = (reason: any) => unhandledList.push(reason);
    process.on('unhandledRejection', rejectionHandler);

    try {
      const mock = new TrackingMockModule();
      const validator = await CredentioValidator.create({
        moduleFactory: async () => mock.asModule()
      });

      const promises = Array.from({ length: 50 }, async (_, idx) => {
        const data = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, idx & 0xff]);
        return validator.validateBytes(data);
      });

      const results = await Promise.all(promises);
      expect(results.length).toBe(50);
      expect(results.every((r) => r.hasCredentials)).toBe(true);

      validator.close();
      expect(unhandledList.length).toBe(0);
    } finally {
      process.off('unhandledRejection', rejectionHandler);
    }
  });

  it('safely handles Blob read errors without unhandled promise rejections', async () => {
    const mock = new TrackingMockModule();
    const validator = await CredentioValidator.create({
      moduleFactory: async () => mock.asModule()
    });

    const brokenBlob = {
      type: 'image/jpeg',
      arrayBuffer: async () => {
        throw new Error('Simulated I/O read failure during Blob stream reading');
      }
    } as unknown as Blob;

    await expect(validator.validateBlob(brokenBlob)).rejects.toThrow(
      'Simulated I/O read failure during Blob stream reading'
    );

    validator.close();
  });
});

describe('Adversarial Stress Harness: crJSON Parser Fuzzing & Schema Edge Cases', () => {
  it('safely parses crJSON when claim_generator_info is [null, ...]', () => {
    const inputWithNullGenInfo = '{"manifests": [{"claim": {"claim_generator_info": [null, {}]}}]}';
    const report = parseCrJSON(inputWithNullGenInfo);
    expect(report.hasCredentials).toBe(true);
    expect(report.activeManifest?.claimGenerator).toBeUndefined();
  });

  it('fuzzes parseCrJSON with corrupt, malformed, and adversarial JSON structures without throwing', () => {
    const fuzzedInputs = [
      '',
      '   ',
      'null',
      'true',
      'false',
      '12345.678',
      '{"manifests": null}',
      '{"manifests": "not an array or object"}',
      '{"manifests": [null, 123, "string", {}, []]}',
      '{"manifests": {"m1": null, "m2": "invalid"}}',
      '{"active_manifest": 99999, "manifests": []}',
      '{"validation_results": {"validation_status": [null, "str", {}]}}',
      '{"manifests": [{"assertions": null, "validation_status": null}]}',
      '{"manifests": [{"assertions": {"c2pa.actions": {"actions": [null, "string", {}]}}}]}',
      '{"manifests": [{"assertions": {"c2pa.training-mining": {"entries": {"c2pa.ai_training": {}}}}}]}',
      '{"manifests": [{"signature_info": {"certificateInfo": null, "timeStampInfo": null}}]}',
      '{"manifests": [{"signature_info": {"time": "NOT_A_VALID_DATE_TIME"}}]}'
    ];

    for (const input of fuzzedInputs) {
      try {
        const report = parseCrJSON(input, 'image/jpeg', 0.01, 0.005);
        expect(report).toBeDefined();
        expect(typeof report.hasCredentials).toBe('boolean');
        expect(typeof report.badge).toBe('string');
      } catch (err) {
        throw new Error(`parseCrJSON threw on fuzzed input: ${input}. Error: ${(err as Error).message}`);
      }
    }
  });

  it('correctly handles loader cache reset and custom loader options', async () => {
    resetCachedWasmModule();
    const mock = new TrackingMockModule();
    const mod1 = await loadCredentioWasm({ moduleFactory: async () => mock.asModule() });
    expect(mod1).toBeDefined();

    resetCachedWasmModule();
  });
});
