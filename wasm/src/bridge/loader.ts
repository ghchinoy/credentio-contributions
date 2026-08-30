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

import type { CredentioEmscriptenModule, WasmInitOptions } from './types.js';

let cachedModulePromise: Promise<CredentioEmscriptenModule> | null = null;

/**
 * Universally loads and initializes the Google Credentio WebAssembly module across
 * Browsers, Web Workers, Node.js (v18+), and Edge Runtimes.
 *
 * @param options Optional configuration including custom locateFile or pre-fetched wasmBinary.
 * @returns Initialized CredentioEmscriptenModule.
 */
export async function loadCredentioWasm(
  options?: WasmInitOptions
): Promise<CredentioEmscriptenModule> {
  if (cachedModulePromise && !options?.wasmBinary && !options?.wasmModule && !options?.moduleFactory) {
    return cachedModulePromise;
  }

  const loaderPromise = (async () => {
    let factory: ((opts?: any) => Promise<CredentioEmscriptenModule>) | undefined;

    if (options?.moduleFactory) {
      factory = options.moduleFactory;
    } else {
      try {
        // Dynamic import of Emscripten glue module from lib/
        // @ts-ignore - Emscripten compiled module in lib/
        const glue = await import('../../lib/credentio.js');
        factory = glue.default || glue.createCredentioModule || glue;
      } catch (err) {
        throw new Error(
          `Failed to load credentio.js WebAssembly glue module: ${(err as Error)?.message || String(err)}. ` +
          `Ensure "make build-wasm" or "./scripts/build-wasm.sh" has been executed to compile native binaries.`
        );
      }
    }

    if (typeof factory !== 'function') {
      throw new Error('WebAssembly module factory is not a callable function.');
    }

    const emscriptenOptions: Record<string, any> = {};

    if (options?.wasmBinary) {
      emscriptenOptions.wasmBinary = options.wasmBinary;
    }

    if (options?.wasmModule) {
      emscriptenOptions.wasmModule = options.wasmModule;
    }

    if (options?.locateFile) {
      emscriptenOptions.locateFile = options.locateFile;
    } else {
      emscriptenOptions.locateFile = (path: string, prefix: string) => {
        if (path.endsWith('.wasm')) {
          // If in Node.js environment, attempt to locate relative to this module
          if (typeof process !== 'undefined' && process.versions?.node) {
            try {
              const url = new URL('../../lib/credentio.wasm', import.meta.url);
              return url.pathname;
            } catch {
              return prefix + path;
            }
          }
        }
        return prefix + path;
      };
    }

    return factory(emscriptenOptions);
  })();

  if (!options?.wasmBinary && !options?.wasmModule && !options?.moduleFactory) {
    cachedModulePromise = loaderPromise;
  }

  return loaderPromise;
}

/**
 * Resets the cached WebAssembly module promise (primarily used for unit testing).
 */
export function resetCachedWasmModule(): void {
  cachedModulePromise = null;
}
