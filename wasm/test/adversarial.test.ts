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
import { sniffMediaType } from '../src/sniff.js';
import { parseCrJSON } from '../src/parser.js';
import { classifyAssertion, getManifestValidity, createProvenanceReport } from '../src/models.js';
import { CredentioValidator } from '../src/validator.js';
import { CredentioWasmBridge } from '../src/bridge/wasm-bridge.js';
import { CredentioError, CredentioStatusCode } from '../src/errors.js';
import type { CredentioEmscriptenModule } from '../src/bridge/types.js';

function createMockEmscriptenModule(options: {
  statusToReturn?: CredentioStatusCode;
  jsonToReturn?: string | null;
  errorMessage?: string;
  coreSeconds?: number;
} = {}): CredentioEmscriptenModule {
  const {
    statusToReturn = CredentioStatusCode.OK,
    jsonToReturn = '{}',
    errorMessage = 'Native error detail',
    coreSeconds = 0.005
  } = options;

  const heap = new Uint8Array(1024 * 1024);
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
    _free(_ptr: number): void {},
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
      return 1001;
    },
    _cr_validator_free(_valPtr: number): void {},
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

describe('Adversarial Test Suite: sniffMediaType Edge Cases', () => {
  it('identifies all 12/13 supported MIME formats and brand variants', () => {
    // 1. JPEG variants
    expect(sniffMediaType(new Uint8Array([0xff, 0xd8, 0xff, 0xe0]))).toBe('image/jpeg');
    expect(sniffMediaType(new Uint8Array([0xff, 0xd8, 0xff, 0xe1]))).toBe('image/jpeg');
    expect(sniffMediaType(new Uint8Array([0xff, 0xd8, 0xff, 0xdb]))).toBe('image/jpeg');

    // 2. PNG
    expect(sniffMediaType(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))).toBe('image/png');

    // 3. GIF
    expect(sniffMediaType(new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x37, 0x61]))).toBe('image/gif'); // GIF87a
    expect(sniffMediaType(new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x39, 0x61]))).toBe('image/gif'); // GIF89a

    // 4. PDF
    expect(sniffMediaType(new TextEncoder().encode('%PDF-2.0'))).toBe('application/pdf');

    // 5. MP3
    expect(sniffMediaType(new Uint8Array([0x49, 0x44, 0x33, 0x04, 0x00]))).toBe('audio/mpeg');

    // 6. FLAC
    expect(sniffMediaType(new Uint8Array([0x66, 0x4c, 0x61, 0x43, 0x00]))).toBe('audio/flac');

    // 7. RIFF formats
    expect(sniffMediaType(new TextEncoder().encode('RIFF\x24\x00\x00\x00WAVE'))).toBe('audio/wav');
    expect(sniffMediaType(new TextEncoder().encode('RIFF\x24\x00\x00\x00WEBP'))).toBe('image/webp');
    expect(sniffMediaType(new TextEncoder().encode('RIFF\x24\x00\x00\x00AVI '))).toBe('video/x-msvideo');

    // 8. ISOBMFF formats
    expect(sniffMediaType(new TextEncoder().encode('....ftypavif'))).toBe('image/avif');
    expect(sniffMediaType(new TextEncoder().encode('....ftypavis'))).toBe('image/avif');
    expect(sniffMediaType(new TextEncoder().encode('....ftypheic'))).toBe('image/heic');
    expect(sniffMediaType(new TextEncoder().encode('....ftypheix'))).toBe('image/heic');
    expect(sniffMediaType(new TextEncoder().encode('....ftypmif1'))).toBe('image/heic');
    expect(sniffMediaType(new TextEncoder().encode('....ftypmsf1'))).toBe('image/heic');
    expect(sniffMediaType(new TextEncoder().encode('....ftypM4A '))).toBe('audio/mp4');
    expect(sniffMediaType(new TextEncoder().encode('....ftypmp42'))).toBe('video/mp4');
    expect(sniffMediaType(new TextEncoder().encode('....ftypisom'))).toBe('video/mp4');
  });

  it('rejects short, empty, null, and boundary-length buffers safely', () => {
    expect(sniffMediaType(null as any)).toBeUndefined();
    expect(sniffMediaType(undefined as any)).toBeUndefined();
    expect(sniffMediaType(new Uint8Array(0))).toBeUndefined();
    expect(sniffMediaType(new Uint8Array([0xff]))).toBeUndefined();
    expect(sniffMediaType(new Uint8Array([0xff, 0xd8]))).toBeUndefined(); // length 2 is < 3
    expect(sniffMediaType(new Uint8Array([0x49, 0x44]))).toBeUndefined(); // MP3 truncated
    expect(sniffMediaType(new Uint8Array([0x66, 0x4c, 0x61]))).toBeUndefined(); // FLAC truncated (3 bytes)
    expect(sniffMediaType(new Uint8Array([0x25, 0x50, 0x44]))).toBeUndefined(); // PDF truncated (3 bytes)
    expect(sniffMediaType(new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x37]))).toBeUndefined(); // GIF truncated (5 bytes)
    expect(sniffMediaType(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a]))).toBeUndefined(); // PNG truncated (7 bytes)
    expect(sniffMediaType(new TextEncoder().encode('RIFF1234WAV'))).toBeUndefined(); // RIFF truncated (11 bytes)
    expect(sniffMediaType(new TextEncoder().encode('1234ftypavi'))).toBeUndefined(); // ISOBMFF truncated (11 bytes)
  });

  it('rejects corrupted or near-miss magic bytes', () => {
    // Near-miss JPEG
    expect(sniffMediaType(new Uint8Array([0xff, 0xd8, 0x00]))).toBeUndefined();
    // Near-miss GIF (GIF88a, GIF90a)
    expect(sniffMediaType(new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x38, 0x61]))).toBeUndefined();
    expect(sniffMediaType(new Uint8Array([0x47, 0x49, 0x46, 0x39, 0x30, 0x61]))).toBeUndefined();
    // Near-miss PNG (byte 7 wrong)
    expect(sniffMediaType(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x00]))).toBeUndefined();
    // Near-miss RIFF subtype
    expect(sniffMediaType(new TextEncoder().encode('RIFF....XYZ1'))).toBeUndefined();
    // Non-RIFF header (RIFX instead of RIFF)
    expect(sniffMediaType(new TextEncoder().encode('RIFX....WAVE'))).toBeUndefined();
    // Non-ftyp ISOBMFF header
    expect(sniffMediaType(new TextEncoder().encode('....moovheic'))).toBeUndefined();
  });
});

describe('Adversarial Test Suite: parseCrJSON Robustness', () => {
  it('handles empty strings, whitespace, and malformed JSON without throwing', () => {
    const inputs = [
      '',
      '   \n\t  ',
      '{',
      '{"manifests": ',
      '{"manifests": [}',
      '<xml><c2pa></c2pa></xml>',
      'undefined',
      'NaN',
      'true',
      'false',
      '12345',
      '"just a string"'
    ];

    for (const input of inputs) {
      const report = parseCrJSON(input, 'image/jpeg');
      expect(report.hasCredentials).toBe(false);
      expect(report.badge).toBe('unsigned');
      expect(report.isVerified).toBe(false);
      expect(report.isInvalid).toBe(false);
      expect(report.activeManifest).toBeUndefined();
    }
  });

  it('handles empty or non-object root JSON payloads gracefully', () => {
    expect(parseCrJSON('{}').hasCredentials).toBe(false);
    expect(parseCrJSON('[]').hasCredentials).toBe(false);
    expect(parseCrJSON('{"manifests": []}').hasCredentials).toBe(false);
    expect(parseCrJSON('{"manifests": null}').hasCredentials).toBe(false);
    expect(parseCrJSON('{"manifests": 12345}').hasCredentials).toBe(false);
    expect(parseCrJSON('{"manifests": "not-array"}').hasCredentials).toBe(false);
  });

  it('handles sparse, corrupt, and non-object elements in manifests array', () => {
    const sparseJson = JSON.stringify({
      manifests: [
        null,
        undefined,
        123,
        'corrupt_manifest_string',
        {},
        { label: 'valid_manifest', title: 'Valid One' }
      ]
    });

    const report = parseCrJSON(sparseJson);
    expect(report.hasCredentials).toBe(true);
    // Two objects: {} (named manifest_4) and valid_manifest
    expect(report.activeManifest?.label).toBe('manifest_4');
    expect(report.ingredientManifests.length).toBe(1);
    expect(report.ingredientManifests[0].label).toBe('valid_manifest');
  });

  it('handles sparse, corrupt, and non-object elements in manifests dictionary', () => {
    const dictJson = JSON.stringify({
      manifests: {
        m1: null,
        m2: 'invalid',
        m3: 999,
        m4: { title: 'Dict Asset' }
      }
    });

    const report = parseCrJSON(dictJson);
    expect(report.hasCredentials).toBe(true);
    expect(report.activeManifest?.label).toBe('m4');
    expect(report.activeManifest?.title).toBe('Dict Asset');
  });

  it('resolves active_manifest correctly across edge cases', () => {
    // 1. active_manifest matches valid label
    const validActive = JSON.stringify({
      active_manifest: 'urn:uuid:target',
      manifests: [
        { label: 'urn:uuid:first' },
        { label: 'urn:uuid:target', title: 'Target Asset' },
        { label: 'urn:uuid:third' }
      ]
    });
    const report1 = parseCrJSON(validActive);
    expect(report1.activeManifest?.label).toBe('urn:uuid:target');
    expect(report1.activeManifest?.title).toBe('Target Asset');
    expect(report1.ingredientManifests.map((m) => m.label)).toEqual([
      'urn:uuid:first',
      'urn:uuid:third'
    ]);

    // 2. active_manifest does not match any label -> fallbacks to first
    const missingActive = JSON.stringify({
      active_manifest: 'urn:uuid:non_existent',
      manifests: [
        { label: 'urn:uuid:first', title: 'First Asset' },
        { label: 'urn:uuid:second' }
      ]
    });
    const report2 = parseCrJSON(missingActive);
    expect(report2.activeManifest?.label).toBe('urn:uuid:first');
    expect(report2.ingredientManifests.length).toBe(1);

    // 3. active_manifest is not a string (e.g. number or object)
    const invalidTypeActive = JSON.stringify({
      active_manifest: 12345,
      manifests: [{ label: 'urn:uuid:only' }]
    });
    const report3 = parseCrJSON(invalidTypeActive);
    expect(report3.activeManifest?.label).toBe('urn:uuid:only');
  });

  it('handles deeply nested manifest stores (e.g. 50 chained ingredients)', () => {
    const count = 50;
    const manifests = Array.from({ length: count }, (_, i) => ({
      label: `urn:uuid:manifest-${i}`,
      title: `Asset ${i}`,
      format: 'image/png'
    }));

    const json = JSON.stringify({
      active_manifest: 'urn:uuid:manifest-25',
      manifests
    });

    const report = parseCrJSON(json);
    expect(report.hasCredentials).toBe(true);
    expect(report.activeManifest?.label).toBe('urn:uuid:manifest-25');
    expect(report.ingredientManifests.length).toBe(49);
    expect(report.ingredientManifests.some((m) => m.label === 'urn:uuid:manifest-25')).toBe(false);
  });

  it('handles generator version edge cases and deduplication', () => {
    // 1. Colon duplicated version
    const jsonDup = JSON.stringify({
      manifests: [
        {
          label: 'm1',
          claim: { claim_generator_info: { name: 'App', version: '888:888' } }
        }
      ]
    });
    expect(parseCrJSON(jsonDup).activeManifest?.claimGenerator).toBe('App 888');

    // 2. Colon distinct version (not duplicated)
    const jsonDiff = JSON.stringify({
      manifests: [
        {
          label: 'm1',
          claim: { claim_generator_info: { name: 'App', version: '1.0:2.0' } }
        }
      ]
    });
    expect(parseCrJSON(jsonDiff).activeManifest?.claimGenerator).toBe('App 1.0:2.0');

    // 3. Three colon tokens
    const jsonThree = JSON.stringify({
      manifests: [
        {
          label: 'm1',
          claim: { claim_generator_info: { name: 'App', version: 'a:b:c' } }
        }
      ]
    });
    expect(parseCrJSON(jsonThree).activeManifest?.claimGenerator).toBe('App a:b:c');

    // 4. Missing version
    const jsonNoVer = JSON.stringify({
      manifests: [
        {
          label: 'm1',
          claim: { claim_generator_info: { name: 'AppOnly' } }
        }
      ]
    });
    expect(parseCrJSON(jsonNoVer).activeManifest?.claimGenerator).toBe('AppOnly');

    // 5. Array generator info with empty version
    const jsonArrayVer = JSON.stringify({
      manifests: [
        {
          label: 'm1',
          claim: { claim_generator_info: [{ name: 'Tool', version: null }] }
        }
      ]
    });
    expect(parseCrJSON(jsonArrayVer).activeManifest?.claimGenerator).toBe('Tool');

    // 6. Direct string claim_generator fallback
    const jsonStrGen = JSON.stringify({
      manifests: [
        {
          label: 'm1',
          claim: { claim_generator: 'DirectGen 2.0' }
        }
      ]
    });
    expect(parseCrJSON(jsonStrGen).activeManifest?.claimGenerator).toBe('DirectGen 2.0');
  });

  it('handles strange, partial, and malformed signature metadata', () => {
    // 1. Invalid date string in time
    const jsonBadDate = JSON.stringify({
      manifests: [
        {
          label: 'm1',
          claim: {
            signature_info: {
              issuer: 'Test Authority',
              time: 'INVALID_NOT_A_DATE'
            }
          }
        }
      ]
    });
    const report1 = parseCrJSON(jsonBadDate);
    expect(report1.activeManifest?.signature?.issuer).toBe('Test Authority');
    expect(report1.activeManifest?.signature?.time).toBeUndefined();

    // 2. Empty signature dictionary
    const jsonEmptySig = JSON.stringify({
      manifests: [{ label: 'm1', claim: { signature_info: {} } }]
    });
    expect(parseCrJSON(jsonEmptySig).activeManifest?.signature).toBeUndefined();

    // 3. Nested certificateInfo with issuer.CN and serialNumber
    const jsonCertInfo = JSON.stringify({
      manifests: [
        {
          label: 'm1',
          claim: {
            signature: {
              certificateInfo: {
                issuer: { CN: 'Embedded Root CA' },
                serialNumber: 'SN-998877'
              },
              alg: 'es384'
            }
          }
        }
      ]
    });
    const report3 = parseCrJSON(jsonCertInfo);
    expect(report3.activeManifest?.signature?.issuer).toBe('Embedded Root CA');
    expect(report3.activeManifest?.signature?.certChainSummary).toBe('SN-998877');
    expect(report3.activeManifest?.signature?.algorithm).toBe('es384');
  });

  it('adversarially tests assertion classification and summarizer resilience', () => {
    // 1. Array vs Dictionary assertions with unusual values
    const jsonAssertions = JSON.stringify({
      manifests: [
        {
          label: 'm1',
          assertions: {
            'c2pa.actions': {
              actions: [
                null,
                123,
                {},
                { action: 'c2pa.created', digital_source_type: 'http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia' },
                { action: 'c2pa.repackaged' }
              ]
            },
            'c2pa.hash.data': { hash_value: 1234567890 },
            'c2pa.author': { author: [{ name: 'Author In Array' }] },
            'c2pa.author.direct': { name: 'Direct Author' },
            'c2pa.author.obj': { author: { name: 'Object Author' } },
            'c2pa.training-mining': { use: 'notAllowed' },
            'c2pa.data-mining.entries': {
              entries: {
                'c2pa.ai_generative_training': 'notAllowed',
                'cawg.data_mining': { use: 'allowed' }
              }
            },
            'c2pa.generative.prompt': { prompt: 'A futuristic city' },
            'c2pa.generative.model': { model: { name: 'ModelX', version: '2' } },
            'c2pa.generative.model_name': { model_name: 'SimpleModel' },
            'c2pa.digital_source_type': { type: 'http://uri/digitalCapture' },
            'unknown.custom.assertion': { foo: 'bar' }
          }
        }
      ]
    });

    const report = parseCrJSON(jsonAssertions);
    const assertions = report.activeManifest?.assertions || [];

    expect(assertions.length).toBe(12);

    const act = assertions.find((a) => a.label === 'c2pa.actions');
    expect(act?.kind).toBe('actions');
    expect(act?.summary).toBe('c2pa.created (trainedAlgorithmicMedia), c2pa.repackaged');

    const hash = assertions.find((a) => a.label === 'c2pa.hash.data');
    expect(hash?.kind).toBe('hash');
    expect(hash?.summary).toBe('hash: 1234567890…');

    const authorArr = assertions.find((a) => a.label === 'c2pa.author');
    expect(authorArr?.summary).toBe('author: Author In Array');

    const authorDir = assertions.find((a) => a.label === 'c2pa.author.direct');
    expect(authorDir?.summary).toBe('author: Direct Author');

    const authorObj = assertions.find((a) => a.label === 'c2pa.author.obj');
    expect(authorObj?.summary).toBe('author: Object Author');

    const tmSimple = assertions.find((a) => a.label === 'c2pa.training-mining');
    expect(tmSimple?.summary).toBe('AI Training: notAllowed');

    const dmEntries = assertions.find((a) => a.label === 'c2pa.data-mining.entries');
    expect(dmEntries?.summary).toBe('AI Training: ai_generative_training=notAllowed, data_mining=allowed');

    const genPrompt = assertions.find((a) => a.label === 'c2pa.generative.prompt');
    expect(genPrompt?.summary).toBe('prompt: A futuristic city');

    const genModel = assertions.find((a) => a.label === 'c2pa.generative.model');
    expect(genModel?.summary).toBe('model: ModelX 2');

    const genModelName = assertions.find((a) => a.label === 'c2pa.generative.model_name');
    expect(genModelName?.summary).toBe('model: SimpleModel');

    const dst = assertions.find((a) => a.label === 'c2pa.digital_source_type');
    expect(dst?.summary).toBe('digitalCapture');

    const unk = assertions.find((a) => a.label === 'unknown.custom.assertion');
    expect(unk?.kind).toBe('other');
    expect(unk?.summary).toBeUndefined();
  });

  it('tests assertion classification categories exhaustively', () => {
    expect(classifyAssertion('c2pa.actions')).toBe('actions');
    expect(classifyAssertion('c2pa.actions.v2')).toBe('actions');
    expect(classifyAssertion('c2pa.ingredient')).toBe('ingredient');
    expect(classifyAssertion('c2pa.thumbnail.claim.jpeg')).toBe('thumbnail');
    expect(classifyAssertion('c2pa.training-mining')).toBe('ai_training_mining');
    expect(classifyAssertion('c2pa.data-mining')).toBe('ai_training_mining');
    expect(classifyAssertion('c2pa.ai_inference')).toBe('ai_training_mining');
    expect(classifyAssertion('c2pa.hash.data')).toBe('hash');
    expect(classifyAssertion('c2pa.hash.bmff.v3')).toBe('hash');
    expect(classifyAssertion('c2pa.metadata')).toBe('metadata');
    expect(classifyAssertion('stds.exif')).toBe('metadata');
    expect(classifyAssertion('stds.schema-org.CreativeWork')).toBe('other');
  });

  it('tests validation severity and badge rollup permutations', () => {
    // 1. Error status -> invalid badge
    expect(getManifestValidity([{ code: 'claimSignature.invalid', severity: 'error' }])).toBe('invalid');
    expect(getManifestValidity([
      { code: 'claimSignature.validated', severity: 'info' },
      { code: 'hash.mismatch', severity: 'error' }
    ])).toBe('invalid');

    // 2. Info and Warning statuses only -> signed badge
    expect(getManifestValidity([
      { code: 'claimSignature.validated', severity: 'info' },
      { code: 'signingCredential.untrusted', severity: 'warning' }
    ])).toBe('signed');

    // 3. Empty statuses -> signed badge (by default)
    expect(getManifestValidity([])).toBe('signed');
  });

  it('inherits root validation status when nested validation status is missing', () => {
    const json = JSON.stringify({
      manifests: [{ label: 'm1' }],
      validation_status: [
        { code: 'claimSignature.missing', explanation: 'No signature found' }
      ]
    });

    const report = parseCrJSON(json);
    expect(report.activeManifest?.validationStatuses.length).toBe(1);
    expect(report.activeManifest?.validationStatuses[0].code).toBe('claimSignature.missing');
    expect(report.activeManifest?.validationStatuses[0].severity).toBe('error');
    expect(report.badge).toBe('invalid');
    expect(report.isInvalid).toBe(true);
  });
});

describe('Adversarial Test Suite: CredentioValidator & Bridge Lifecycle', () => {
  it('rejects various invalid buffer types and sizes', async () => {
    const mock = createMockEmscriptenModule();
    const val = await CredentioValidator.create({ moduleFactory: async () => mock });

    // Empty Uint8Array
    await expect(val.validateBytes(new Uint8Array(0))).rejects.toThrow(CredentioError);
    // Empty ArrayBuffer
    await expect(val.validateBytes(new ArrayBuffer(0))).rejects.toThrow('Input byte buffer cannot be empty.');

    // Empty Blob
    const emptyBlob = new Blob([]);
    await expect(val.validateBlob(emptyBlob)).rejects.toThrow(CredentioError);

    val.close();
  });

  it('handles typed array views (ArrayBuffer conversions)', async () => {
    const mock = createMockEmscriptenModule({
      jsonToReturn: JSON.stringify({ manifests: [{ label: 'm1', format: 'image/png' }] })
    });
    const val = await CredentioValidator.create({ moduleFactory: async () => mock });

    const buffer = new ArrayBuffer(16);
    const view = new Uint8Array(buffer);
    view.set([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

    const report = await val.validateBytes(buffer);
    expect(report.hasCredentials).toBe(true);
    expect(report.mediaType).toBe('image/png');

    val.close();
  });

  it('rejects calls after close and allows multiple close calls without crashing', async () => {
    const mock = createMockEmscriptenModule();
    const val = await CredentioValidator.create({ moduleFactory: async () => mock });

    expect(val.isOpen).toBe(true);
    val.close();
    expect(val.isOpen).toBe(false);

    // Second close is no-op
    expect(() => val.close()).not.toThrow();

    // Invocations fail with CredentioError
    await expect(val.validateBytes(new Uint8Array([1, 2, 3]))).rejects.toThrow(
      'Validator instance has already been closed.'
    );
  });

  it('handles bridge creation with custom trust PEMs and trust check flags', () => {
    const mock = createMockEmscriptenModule();
    const claimPem = '-----BEGIN CERTIFICATE-----\nMIIB...\n-----END CERTIFICATE-----';
    const tsaPem = '-----BEGIN CERTIFICATE-----\nMIIC...\n-----END CERTIFICATE-----';

    const bridge = new CredentioWasmBridge(mock, claimPem, tsaPem, false);
    expect(bridge.isOpen).toBe(true);
    expect(bridge.getVersion()).toBe('1.4.2-wasm');
    bridge.close();
  });

  it('surfaces IO_ERROR and INVALID_ARGUMENT status codes accurately', async () => {
    // 1. IO_ERROR
    const mockIO = createMockEmscriptenModule({
      statusToReturn: CredentioStatusCode.IO_ERROR,
      errorMessage: 'Failed to read media box stream'
    });
    const valIO = await CredentioValidator.create({ moduleFactory: async () => mockIO });

    await expect(valIO.validateBytes(new Uint8Array([1, 2, 3, 4]))).rejects.toMatchObject({
      name: 'CredentioError',
      statusCode: CredentioStatusCode.IO_ERROR,
      message: expect.stringContaining('Validation failed (status 3): Failed to read media box stream')
    });
    valIO.close();

    // 2. INVALID_ARGUMENT
    const mockArg = createMockEmscriptenModule({
      statusToReturn: CredentioStatusCode.INVALID_ARGUMENT,
      errorMessage: 'Unsupported stream framing'
    });
    const valArg = await CredentioValidator.create({ moduleFactory: async () => mockArg });

    await expect(valArg.validateBytes(new Uint8Array([1, 2, 3, 4]))).rejects.toMatchObject({
      name: 'CredentioError',
      statusCode: CredentioStatusCode.INVALID_ARGUMENT,
      message: expect.stringContaining('Validation failed (status 2): Unsupported stream framing')
    });
    valArg.close();
  });
});
