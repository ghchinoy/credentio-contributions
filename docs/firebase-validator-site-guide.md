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

# Credentio Web Validator Site Guide (`credentio-validator-web`)

This document outlines the scaffolding, architecture, and deployment procedures for creating the standalone web validator application in a separate repository (`ghchinoy/credentio-validator-web`) deployed to Firebase Hosting.

> **Disclaimer:** This project is an open-source community contribution and is not an officially supported Google product.

---

## 1. Architectural Architecture

- **Client-Side Execution:** Media validation runs 100% locally in the browser via WebAssembly (`@ghchinoy/credentio-wasm`). Zero bytes leave the client.
- **Single-Threaded Engine:** Compiled with `-sUSE_PTHREADS=0`, enabling universal browser execution without requiring `Cross-Origin-Opener-Policy` (COOP) or `Cross-Origin-Embedder-Policy` (COEP) headers.
- **Static Asset Hosting:** Hosted via Google Firebase Hosting with global CDN caching.

---

## 2. Project Scaffolding

### `package.json`

```json
{
  "name": "credentio-validator-web",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "@ghchinoy/credentio-wasm": "^0.1.5"
  },
  "devDependencies": {
    "typescript": "^5.7.0",
    "vite": "^6.0.0"
  }
}
```

### `vite.config.ts`

```typescript
import { defineConfig } from 'vite';

export default defineConfig({
  assetsInclude: ['**/*.wasm'],
  server: {
    port: 3000
  },
  build: {
    target: 'esnext',
    outDir: 'dist'
  }
});
```

### `firebase.json`

```json
{
  "hosting": {
    "public": "dist",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "headers": [
      {
        "source": "**/*.wasm",
        "headers": [
          {
            "key": "Content-Type",
            "value": "application/wasm"
          },
          {
            "key": "Cache-Control",
            "value": "public, max-age=31536000, immutable"
          }
        ]
      }
    ],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ]
  }
}
```

---

## 3. Core Validation Component (`src/validator.ts`)

```typescript
import { CredentioValidator, type ProvenanceReport } from '@ghchinoy/credentio-wasm';

let validatorInstance: CredentioValidator | null = null;

export async function getValidator(): Promise<CredentioValidator> {
  if (!validatorInstance) {
    validatorInstance = await CredentioValidator.create({
      skipTrustChecks: true
    });
  }
  return validatorInstance;
}

export async function validateUserFile(file: File): Promise<ProvenanceReport> {
  const validator = await getValidator();
  return validator.validateBlob(file);
}
```

---

## 4. Local Development & Deployment

### Step 1: Install Dependencies & Run Dev Server

```bash
npm install
npm run dev
```

### Step 2: Validate with Firebase Local Emulator

```bash
npm run build
firebase emulators:start --only hosting
```

### Step 3: Deploy to Firebase Hosting

```bash
# Manual Deploy:
firebase deploy --only hosting

# Deploy to Preview Channel (for testing PRs):
firebase hosting:channel:deploy preview-test
```

---

## 5. Automated CI/CD (`.github/workflows/deploy.yml`)

```yaml
name: Deploy to Firebase Hosting

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm

      - name: Install Dependencies
        run: npm ci

      - name: Build Web Application
        run: npm run build

      - name: Deploy to Firebase Hosting (Live Channel)
        if: github.ref == 'refs/heads/main' && github.event_name == 'push'
        uses: FirebaseExtended/action-hosting-deploy@v0
        with:
          repoToken: '${{ secrets.GITHUB_TOKEN }}'
          firebaseServiceAccount: '${{ secrets.FIREBASE_SERVICE_ACCOUNT }}'
          channelId: live
          projectId: '${{ secrets.FIREBASE_PROJECT_ID }}'

      - name: Deploy to Firebase Hosting (Preview Channel)
        if: github.event_name == 'pull_request'
        uses: FirebaseExtended/action-hosting-deploy@v0
        with:
          repoToken: '${{ secrets.GITHUB_TOKEN }}'
          firebaseServiceAccount: '${{ secrets.FIREBASE_SERVICE_ACCOUNT }}'
          expires: 7d
          projectId: '${{ secrets.FIREBASE_PROJECT_ID }}'
```
