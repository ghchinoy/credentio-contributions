<!--
Copyright 2026 Google LLC

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-->

# Cloudflare Workers C2PA Edge Gatekeeper Guide

This guide walks through creating, testing locally (`wrangler dev`), and deploying a Cloudflare Worker that verifies and signs C2PA Content Credentials at the edge using `@ghchinoy/credentio-wasm`.

> **Disclaimer:** This project is an open-source community contribution and is not an officially supported Google product.

---

## 1. How WebAssembly Works in Cloudflare Workers (`workerd`)

Cloudflare Workers blocks runtime WebAssembly compilation from raw byte arrays (`WebAssembly.compile` / `fetch('credentio.wasm')`) for security. Instead, Cloudflare Wrangler compiles `.wasm` imports at deploy time into a `WebAssembly.Module` object.

`@ghchinoy/credentio-wasm` exports `./wasm` (`lib/credentio.wasm`) and accepts `wasmModule` on both `CredentioValidator.create({ wasmModule })` and `CredentioSigner.create({ wasmModule, ... })`, wiring up Emscripten's `instantiateWasm` hook automatically.

> **Bundle Size Note:** `credentio.wasm` is ~7.8 MB uncompressed (~2.4 MB gzipped). This fits within Cloudflare Workers' 3 MB Free tier compressed limit and well within the 10 MB Workers Paid limit.

---

## 2. Project Scaffolding

### Step 1: Initialize the Worker Directory

```bash
mkdir credentio-cf-worker && cd credentio-cf-worker
npm init -y

# Install @ghchinoy/credentio-wasm from the v0.2.2 GitHub Release tarball:
npm install https://github.com/ghchinoy/credentio-contributions/releases/download/v0.2.2/ghchinoy-credentio-wasm-0.2.2.tgz

# Install Cloudflare Wrangler and TypeScript types:
npm install -D wrangler @cloudflare/workers-types typescript
```

### Step 2: Create `wrangler.toml`

```toml
name = "credentio-c2pa-worker"
main = "src/index.ts"
compatibility_date = "2026-10-01"
compatibility_flags = ["nodejs_compat"]
```

### Step 3: Create `tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "lib": ["ES2022"],
    "types": ["@cloudflare/workers-types"],
    "strict": true,
    "noEmit": true
  },
  "include": ["src/**/*.ts"]
}
```

### Step 4: Create `src/wasm.d.ts` (TypeScript Declaration for `.wasm` Import)

```typescript
declare module '@ghchinoy/credentio-wasm/wasm' {
  const value: WebAssembly.Module;
  export default value;
}
```

### Step 5: Create `src/index.ts`

```typescript
import { CredentioValidator } from '@ghchinoy/credentio-wasm';
import credentioWasm from '@ghchinoy/credentio-wasm/wasm';

export default {
  async fetch(request: Request): Promise<Response> {
    if (request.method !== 'POST') {
      return Response.json({
        service: 'Credentio C2PA Edge Verifier',
        usage: 'POST a media file body (image/jpeg, image/png, video/mp4, application/pdf) to verify C2PA credentials.',
      });
    }

    const mediaBytes = await request.arrayBuffer();
    if (mediaBytes.byteLength === 0) {
      return Response.json({ error: 'Empty request body' }, { status: 400 });
    }

    using validator = await CredentioValidator.create({
      wasmModule: credentioWasm,
      skipTrustChecks: true,
    });

    const contentType = request.headers.get('content-type') || undefined;
    const report = await validator.validateBytes(mediaBytes, contentType);

    return Response.json(report, {
      headers: {
        'X-C2PA-Badge': report.badge,
        'X-C2PA-Core-Ms': ((report.coreSeconds ?? 0) * 1000).toFixed(2),
      },
    });
  },
};
```

---

## 3. Local Testing & Cloudflare Deployment

### 1. Run Locally with `wrangler dev`

```bash
npx wrangler dev
```

### 2. Test with `curl` (Sign an Image & Verify at the Edge)

In a second terminal, sign a test image with `credentialctl` and `POST` it to your local Worker:

```bash
# Sign a PNG image in-process:
credentialctl sign input.png -o signed.png

# Verify the signed image against the local Cloudflare Worker:
curl -s -X POST --data-binary @signed.png \
  -H "Content-Type: image/png" \
  http://localhost:8787 | jq .
```

### 3. Deploy to Your Cloudflare Account

```bash
# Authenticate with Cloudflare (opens browser on first run):
npx wrangler login

# Deploy to <name>.<your-subdomain>.workers.dev:
npx wrangler deploy
```
