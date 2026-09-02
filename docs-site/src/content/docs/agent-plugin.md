---
title: Agent Plugin & Skill (c2pa-inspector)
description: Audit single media assets, batches, and directories for C2PA Content Credentials and AI provenance using autonomous Agent Plugins.
---

# Agent Plugin: C2PA Inspector (`c2pa-inspector`)

An [Agent Plugins v1.0.0](https://github.com/agentplugins/agent-plugins-spec) specification package and [Agent Skill](https://agentskills.io/specification.md) providing autonomous C2PA Content Credentials inspection, verification, and batch auditing capabilities for AI agents and developers.

> **Disclaimer:** This project is an open-source community contribution and is not an officially supported Google product.

---

## Overview

The `c2pa-inspector` plugin enables autonomous coding agents (such as Jetski, Claude Code, Gemini, or Copilot) and command-line developers to inspect media assets (images, videos, audio, and documents) for embedded C2PA provenance metadata. Built on [Google Credentio](https://mediaprovenance.googlesource.com/credentio/) data models and C-ABI wrapper architecture, it audits cryptographic assertions, claim generators, signing certificates, and AI generation or training flags.

### Key Capabilities

- **Single and Multi-Asset Auditing:** Inspect single files, explicit lists of paths, or entire directory trees recursively.
- **Dual-Engine Architecture:** Uses native Google Credentio C-ABI via CFFI for full cryptographic trust validation when available, paired with a zero-dependency pure-Python container and JUMBF parser fallback for lightweight sandboxes.
- **AI Provenance and Training Consent:** Detects generative AI attribution (`trainedAlgorithmicMedia`), generative model prompts, and training or mining restrictions (`c2pa.ai_generative_training`, `cawg.data_mining`).
- **Structured JSON for Agents:** Emits machine-readable JSON schemas optimized for LLM tool calling and automated evaluation pipelines.
- **Specification Conformance:** Conforms strictly to the Agent Plugins v1.0.0 Specification and Agent Skills Specification.

---

## Directory Structure

The plugin lives under `plugins/c2pa-inspector/` adhering strictly to Agent Plugins v1.0.0 §4.1 package containment:

```text
plugins/c2pa-inspector/
├── plugin.json               # Agent Plugins v1.0.0 package manifest
├── LICENSE                   # Apache 2.0 license
├── README.md                 # Plugin overview and usage guide
└── skills/
    └── c2pa-inspect/         # Core inspection skill
        ├── SKILL.md          # Skill instructions for autonomous agents
        ├── scripts/
        │   ├── inspect_c2pa.py       # Dual-engine batch inspector and CLI
        │   └── fetch_native_lib.sh   # Prebuilt libcredentio_c binary fetcher
        ├── references/
        │   ├── c2pa-spec-guide.md    # C2PA assertions, schemas, and taxonomies
        │   ├── badge-states.md       # Validation criteria and status semantics
        │   └── ai-provenance.md      # AI attribution and training-mining guide
        └── assets/
            ├── sample_crjson_v1.json # C2PA v1 sample manifest fixture
            ├── sample_crjson_v2.json # C2PA v2 sample manifest fixture
            └── sample_ai_manifest.json # AI provenance metadata fixture
```

---

## Agent Discovery and Installation

Autonomous agents discover the skill automatically when working in the repository or through the [Agent Skills CLI](https://agentskills.io):

### 1. Repository Discovery
When an agent operates inside `credentio-contributions` or `agent-skills`, the skill is located at:
`plugins/c2pa-inspector/skills/c2pa-inspect/SKILL.md`

### 2. Marketplace Installation
The plugin is indexed in the Claude Plugin Marketplace:

```json
{
  "name": "c2pa-inspector",
  "source": "./plugins/c2pa-inspector",
  "description": "Inspect and audit C2PA Content Credentials, cryptographic signatures, provenance assertions, and AI generation metadata across media assets",
  "skills": [
    "./plugins/c2pa-inspector/skills/c2pa-inspect"
  ]
}
```

---

## Command-Line Usage

The skill provides the `inspect_c2pa.py` script, which can be executed directly by agents or developers.

### 1. Inspect a Single Asset

```bash
python3 plugins/c2pa-inspector/skills/c2pa-inspect/scripts/inspect_c2pa.py photo.jpg
```

Output detail card:
```text
====================================================================
  C2PA Provenance Report: photo.jpg
====================================================================
Path:        /workspace/photo.jpg
Size:        1.4 MB (1472810 bytes)
Media Type:  image/jpeg
Engine:      Google Credentio (C-ABI) (credentio_native_c)
Status:      SIGNED
Credentials: Present
Manifest:    urn:uuid:active-manifest-001
Title:       Landscape Sunset
Generator:   Credentio C2PA Tool 1.4.2
Issuer:      Google Authenticity CA
Algorithm:   es256
Signed Time: 2026-08-30T12:00:00+00:00
Assertions:  3 attached
--------------------------------------------------------------------
  Validation Details:
  [INFO] claimSignature.validated: Signature is cryptographically valid
Elapsed:     3.12 ms
====================================================================
```

### 2. Multi-Asset Batch Table

```bash
python3 plugins/c2pa-inspector/skills/c2pa-inspect/scripts/inspect_c2pa.py \
  photo1.jpg graphic2.png video3.mp4
```

Output:
```text
====================================================================================================
STATUS     ASSET                      FORMAT         GENERATOR              AI ATTRIBUTION          
====================================================================================================
SIGNED     photo1.jpg                 image/jpeg     Credentio C2PA Tool .. Human Capture           
SIGNED     graphic2.png               image/png      Photoshop 26.1.0       Human Capture           
SIGNED     video3.mp4                 video/mp4      GenAI Studio 3.0       AI Generated            
====================================================================================================
Total Scanned: 3
  SIGNED:      3 (100.0%)
  UNSIGNED:    0 (0.0%)
  INVALID:     0 (0.0%)
  AI ATTR:     1 (33.3%)
====================================================================================================
```

### 3. Recursive Directory Scanning

Scan an entire media directory tree:

```bash
python3 plugins/c2pa-inspector/skills/c2pa-inspect/scripts/inspect_c2pa.py \
  --dir ./assets --recursive
```

### 4. Machine-Readable JSON for Agent Pipelines

Pass `--json` to produce structured output for automated decision-making:

```bash
python3 plugins/c2pa-inspector/skills/c2pa-inspect/scripts/inspect_c2pa.py \
  --dir ./assets --recursive --json
```

Output JSON structure:

```json
{
  "summary": {
    "total_scanned": 12,
    "reported_count": 12,
    "signed_count": 10,
    "unsigned_count": 2,
    "invalid_count": 0,
    "ai_attributed_count": 4
  },
  "assets": [
    {
      "asset_path": "/workspace/assets/image.jpg",
      "byte_size": 204850,
      "media_type": "image/jpeg",
      "engine_id": "credentio_native_c",
      "engine_name": "Google Credentio (C-ABI)",
      "has_credentials": true,
      "badge": "signed",
      "spec_version": "2.2",
      "elapsed_seconds": 0.0034,
      "active_manifest": {
        "label": "urn:c2pa:manifest",
        "title": "Generated Artwork",
        "claim_generator": "GenAI Studio 3.0",
        "format": "image/jpeg",
        "signature": {
          "issuer": "AI Content CA",
          "algorithm": "es256",
          "time": "2026-08-30T14:00:00+00:00",
          "cert_serial_number": "11223344"
        },
        "ai_provenance": {
          "digital_source_type": "https://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia",
          "generative_model": {
            "name": "Imagen",
            "version": "3.0"
          },
          "prompt": "A tranquil mountain lake at dawn"
        },
        "assertions_count": 4,
        "validation_statuses_count": 1
      }
    }
  ]
}
```

### 5. Status and AI Provenance Filtering

Filter results by status or AI attribution flags:

```bash
# Filter only assets with generative AI origin or training opt-outs
python3 plugins/c2pa-inspector/skills/c2pa-inspect/scripts/inspect_c2pa.py \
  --dir ./media --recursive --filter ai-only

# Filter only unsigned assets requiring credentials before publication
python3 plugins/c2pa-inspector/skills/c2pa-inspect/scripts/inspect_c2pa.py \
  --dir ./media --recursive --filter unsigned
```

---

## Dual-Engine Architecture

```text
+-------------------------------------------------------------+
|               Target Media File(s) or Directory             |
+-------------------------------------------------------------+
                               |
               [ Native libcredentio_c Present? ]
               /                                \
             Yes                                 No
            /                                     \
+-------------------------------+   +-------------------------------+
| Credentio C-ABI Native Engine |   | Credentio Container Fallback  |
| - libcredentio_c via CFFI     |   | - Pure Python (zero deps)     |
| - Complete cryptographic trust|   | - JPEG APP11 JUMBF box parser |
| - X.509 cert chain validation |   | - PNG caPt/caPI chunk scanner |
| - Media byte hash verification|   | - MP4/MOV uuid box extractor  |
| - Sub-millisecond speed       |   | - Manifest claims & AI flags  |
+-------------------------------+   +-------------------------------+
            \                                     /
             +------------------+----------------+
                                |
                   [ Unified Provenance Report ]
                                |
             +------------------+----------------+
             |                                   |
    [ Human Table Output ]              [ Structured JSON ]
```

1. **Native Credentio C-ABI Engine:**
   When `libcredentio_c.so` or `libcredentio_c.dylib` is available, the script loads it through CFFI to execute complete cryptographic validation. It evaluates RSA/ECDSA digital signatures, X.509 certificate chains, RFC 3161 timestamps, and BMFF byte hashes in 3 to 5 milliseconds per file.
2. **Pure-Python Container Fallback:**
   When operating in lightweight container environments or agent sandboxes without Bazel or compiled libraries, the script inspects media container boxes directly in pure Python. It identifies JUMBF superboxes, extracts claim generators, assertion counts, digital source types, and training consent markers without failing.

---

## Exit Codes

The tool adheres to standard automation exit codes for reliable scripting:

| Code | State | Description |
|---|---|---|
| `0` | `SUCCESS` | All examined files with credentials are valid, or clean scan. |
| `1` | `UNSIGNED` | One or more files lack credentials (when evaluated under `--filter signed`). |
| `2` | `INVALID` | One or more files contain corrupted, modified, or invalid credentials. |
| `3` | `ERROR` | Target file or directory not found, or invalid argument syntax. |
