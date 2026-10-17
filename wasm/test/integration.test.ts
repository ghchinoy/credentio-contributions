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

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { loadCredentioWasm } from '../src/bridge/loader.js';
import { CredentioSigner } from '../src/signer.js';
import { CredentioValidator } from '../src/validator.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const wasmLibPath = path.resolve(__dirname, '../lib/credentio.wasm');

const hasWasmBinary = fs.existsSync(wasmLibPath);

describe.runIf(hasWasmBinary)('Credentio WebAssembly Native Integration Suite', () => {
  it('loads real compiled WebAssembly binary and verifies C-ABI version string', async () => {
    const wasmModule = await loadCredentioWasm();
    expect(wasmModule).toBeDefined();

    const versionPtr = wasmModule._cr_version();
    expect(versionPtr).toBeGreaterThan(0);

    const versionStr = wasmModule.UTF8ToString(versionPtr);
    expect(versionStr).toContain('credentio');
  });

  it('instantiates real native CredentioValidator and validates uncredentialed JPEG buffer', async () => {
    const validator = await CredentioValidator.create();
    expect(validator.isOpen).toBe(true);

    const jpegBytes = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);
    const report = await validator.validateBytes(jpegBytes);

    expect(report.engineId).toBe('credentio-wasm');
    expect(report.engineName).toBe('Credentio (WebAssembly)');
    expect(report.hasCredentials).toBe(false);
    expect(report.badge).toBe('unsigned');
    expect(report.mediaType).toBe('image/jpeg');
    expect(report.coreSeconds).toBeGreaterThan(0);
    expect(report.elapsedSeconds).toBeGreaterThan(0);

    validator.close();
    expect(validator.isOpen).toBe(false);
  });

  it('validates standard Blob inputs with real WebAssembly engine', async () => {
    const validator = await CredentioValidator.create();

    const pngHeader = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    const blob = new Blob([pngHeader], { type: 'image/png' });

    const report = await validator.validateBlob(blob);
    expect(report.hasCredentials).toBe(false);
    expect(report.mediaType).toBe('image/png');
    expect(report.badge).toBe('unsigned');

    validator.close();
  });

  it('supports Explicit Resource Management via Symbol.dispose on native engine', async () => {
    const validator = await CredentioValidator.create();
    expect(validator.isOpen).toBe(true);

    validator[Symbol.dispose]();
    expect(validator.isOpen).toBe(false);
  });

  it('signs a PNG in memory with CredentioSigner and verifies it with CredentioValidator', async () => {
    const claimSignerKeyPem = [
      '-----BEGIN PRIVATE KEY-----',
      'MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgP1t9Nc4kMdAQMHs5',
      'DjHjrBFHRIOC24W+tvrPF3gS1JWhRANCAAQ+mATlGlQUDF4bGnJvbd5ehII2+Hnu',
      'r+O6rqzDEiG+yWvazpNchCzDXds0DQAe7nsq1Jbd6qbZaab4eJMYakbO',
      '-----END PRIVATE KEY-----'
    ].join('\n');

    const claimSignerCertPem = [
      '-----BEGIN CERTIFICATE-----',
      'MIIB7jCCAZSgAwIBAgIQNX8XBvVYTVppX0cFOnohFzAKBggqhkjOPQQDAjA6MRcw',
      'FQYDVQQKEw5DcmVkZW50aW8gVGVzdDEfMB0GA1UEAxMWQ3JlZGVudGlvIFRlc3Qg',
      'Um9vdCBDQTAeFw0yNjEwMTcxODI0NTRaFw0yNzEwMTcxODI0NTRaMD8xFzAVBgNV',
      'BAoTDkNyZWRlbnRpbyBUZXN0MSQwIgYDVQQDExtDcmVkZW50aW8gVGVzdCBDbGFp',
      'bSBTaWduZXIwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAQ+mATlGlQUDF4bGnJv',
      'bd5ehII2+Hnur+O6rqzDEiG+yWvazpNchCzDXds0DQAe7nsq1Jbd6qbZaab4eJMY',
      'akbOo3cwdTAOBgNVHQ8BAf8EBAMCB4AwFQYDVR0lBA4wDAYKKwYBBAGD6F4CATAM',
      'BgNVHRMBAf8EAjAAMB0GA1UdDgQWBBQFXmMIouQm0lMTvkeJO2iPSyhm2jAfBgNV',
      'HSMEGDAWgBSXI/fOmvyeRDvJE0mnuXPhzwfY6jAKBggqhkjOPQQDAgNIADBFAiEA',
      '1QoxfwjNbRyWPhypgSxLFkwhUAeqSDNPybpo8+hnVMECIA+pv4x+d0Yey3G2xbg5',
      'qUlmi2S1eV8f19ACqbGCN0er',
      '-----END CERTIFICATE-----'
    ].join('\n');

    const minimalPng = new Uint8Array([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xde,
      0x00, 0x00, 0x00, 0x0c, 0x49, 0x44, 0x41, 0x54,
      0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0x00, 0x00,
      0x03, 0x01, 0x01, 0x00, 0x18, 0xdd, 0x8d, 0xb0,
      0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44,
      0xae, 0x42, 0x60, 0x82
    ]);

    const signer = await CredentioSigner.create({
      claimSignerKeyPem,
      claimSignerCertPem,
      generatorName: 'WasmCredentioSigner',
      generatorVersion: '0.2.0'
    });
    expect(signer.isOpen).toBe(true);

    const signResult = await signer.signBytes(minimalPng, {
      mediaType: 'image/png',
      digitalSourceType: 'http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture',
      customAssertions: {
        'c2pa.training-mining': {
          entries: {
            'c2pa.ai_generative_training': { use: 'notAllowed' }
          }
        }
      }
    });
    expect(signResult.byteSize).toBeGreaterThan(minimalPng.byteLength);
    expect(signResult.signedBytes.byteLength).toBe(signResult.byteSize);
    signer.close();
    expect(signer.isOpen).toBe(false);

    const validator = await CredentioValidator.create({ skipTrustChecks: true });
    const report = await validator.validateBytes(signResult.signedBytes, 'image/png');
    expect(report.hasCredentials).toBe(true);
    expect(report.badge).toBe('signed');
    expect(report.primaryClaimGenerator).toContain('WasmCredentioSigner');
    validator.close();
  });
});
