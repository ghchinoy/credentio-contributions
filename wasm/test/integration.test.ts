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
});
