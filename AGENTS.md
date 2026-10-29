# AGENTS.md: Contributor and Agent Guide

This document outlines the repository structure, common commands, and the documentation quality workflow for agents and developers working on `credentio-contributions`.

---

## 1. Project Overview and Structure

This repository provides native language bindings for [Google Credentio](https://mediaprovenance.googlesource.com/credentio/) built on a shared `extern "C"` Application Binary Interface (C-ABI):

- **`native/`**: The core C-ABI wrapper (`credentio_c.h`, `credentio_c.cc`, `BUILD`) and Clang modulemap.
- **`python/`**: Python package (`credentio`) using `cffi`, typed dataclasses, and CLI entry point.
- **`go/`**: Go package (`github.com/ghchinoy/credentio-contributions/go`) using `cgo` and standalone CLI.
- **`swift/`**: Standalone SwiftPM package (`CredentioKit`) with actor-isolated native engines and CLI.
- **`wasm/`**: Isomorphic TypeScript SDK (`@ghchinoy/credentio-wasm`) and Emscripten WebAssembly build.
- **`plugins/`**: Agent Plugins v1.0.0 packages (`c2pa-inspector`) providing autonomous agent skills for C2PA provenance auditing.
- **`docs-site/`**: Interactive documentation portal built with [Astro Starlight](https://starlight.astro.build/) and the Catppuccin theme.
- **`docs/`**: Developer architecture guides and Architecture Decision Records (`docs/adr/`).
- **`scripts/`**: Automation scripts for building shared libraries and XCFrameworks via Bazel.

---

## 2. The Documentation and Quality Loop (TL;DR)

Whenever creating, updating, or reviewing documentation:

1. **Write or Edit Docs:**
   Update documentation pages under `docs-site/src/content/docs/`, guides under `docs/`, or language `README.md` files.
2. **Run Docstats and Editorial Linting:**
   Run the `technical-post-editorial` evaluation using [docstats](https://github.com/ghchinoy/docstats) to audit prose for house style, active voice, and plain language (target score: 9.0 to 10.0 / 10; hard floor >= 7.0). Ensure zero em dashes in prose.
3. **Score README Changes:**
   When writing or updating READMEs, evaluate against the Mark Allen quality rubric (`make-readme` skill; target score: >= 34 / 40, Excellent band).
4. **Verify Static Build:**
   Run `make docs-build` to ensure Astro Starlight generates all routes, search indexes (Pagefind), and site maps without broken references or link errors.
5. **Commit and Push Separately:**
   Stage files cleanly, create a concise descriptive commit, and verify with `git status` before pushing.

---

## 3. Running Docstats and Editorial Skills

The authoring tools live in [docstats](https://github.com/ghchinoy/docstats) and [agent-skills](https://github.com/ghchinoy/agent-skills):

### Run Docstats Scorecard on Documentation
```bash
# Clone docstats and run the scorecard:
git clone https://github.com/ghchinoy/docstats.git
export DOCSTATS_DIR="$(pwd)/docstats"

uv run --directory "$DOCSTATS_DIR" python -c "
import sys, os
sys.path.insert(0, os.environ['DOCSTATS_DIR'])
from metrics import _sync_analyze_document

files = ['docs-site/src/content/docs/why.md', 'README.md']
for f in files:
    with open(f, 'r', encoding='utf-8') as fp:
        raw = fp.read()
    parts = raw.split('---', 2)
    text = parts[2] if len(parts) >= 3 else raw
    res = _sync_analyze_document(text, f)
    print(f'{f}: Grade={res.readability.flesch_kincaid_grade:.1f}, Style Score={res.ai_patterns.ai_tell_score:.1f}/10, EmDashes={res.ai_patterns.em_dash_count}')
"
```

### Reference Agent Skills
- **Technical Post Editorial:** [SKILL.md](https://github.com/ghchinoy/agent-skills/blob/main/plugins/repo-authoring/skills/technical-post-editorial/SKILL.md)
- **Make README Rubric:** [SKILL.md](https://github.com/ghchinoy/agent-skills/blob/main/plugins/repo-authoring/skills/make-readme/SKILL.md)

---

## 4. Common Build and Test Commands

```bash
# Check if upstream Google Credentio has advanced beyond .credentio-pin:
make check-drift

# Download prebuilt native shared library from GitHub Releases (for Python & Go):
make fetch-lib

# Build native dynamic shared library (.dylib on macOS, .so on Linux for Python & Go):
make build-lib

# Build native static XCFramework (for Swift on macOS):
make build-swift

# Build native WebAssembly binary (credentio.wasm & credentio.js via Bazel + @emsdk):
make build-wasm

# Run test suites:
make python-test   # Run Python pytest suite (uses uv automatically if installed)
make go-test       # Run Go test suite (CGO_ENABLED=1)
make swift-test    # Run Swift test suite
make wasm-test     # Build TypeScript SDK and run Vitest suite
make test          # Run Python, Go, Swift, and WASM test suites

# Refresh local prebuilt Swift XCFramework and WASM binaries from a GitHub Release (without a full Bazel build):
# Note: swift/Package.swift prioritizes a local swift/CredentioC.xcframework directory if present on disk.
# If swift/CredentioC.xcframework is stale (e.g. from an older release), remove it or unpack the latest release zip:
gh release download v0.2.2 -p 'CredentioC.xcframework.zip' -p 'credentio.wasm' -p 'credentio.js' -D /tmp --clobber
rm -rf swift/CredentioC.xcframework && unzip -q /tmp/CredentioC.xcframework.zip -d swift/
cp /tmp/credentio.wasm /tmp/credentio.js wasm/lib/ && cp /tmp/credentio.wasm /tmp/credentio.js wasm/dist/

# Documentation site (Astro Starlight):
make docs-serve    # Launch local development server
make docs-build    # Compile production static build in docs-site/dist/

# Clean build artifacts:
make clean
```

---

## 5. Key Conventions and Guardrails

1. **Copyright and Licensing:**
   Every source file must begin with the standard Google LLC Apache 2.0 copyright header.
2. **Disclaimer:**
   Public-facing documents and READMEs must carry the standard disclaimer: *"This project is an open-source community contribution and is not an officially supported Google product."*
3. **Repository Identity:**
   The repository owner is `ghchinoy` (`github.com/ghchinoy/credentio-contributions`). Upstream Google Credentio is `mediaprovenance.googlesource.com/credentio` and should be linked when referencing authoritative C++ source or specifications.
4. **Two-Step Release & Prebuilt Distribution Workflow:**
   Compiled binaries (`libcredentio_c.{dylib,so}`, `CredentioC.xcframework.zip`, `credentio.wasm`, Python wheels, and `ghchinoy-credentio-wasm-<ver>.tgz`) are `.gitignore`d and distributed via GitHub Releases. To avoid CI chicken-and-egg failures when cutting a new release `vX.Y.Z`, always use two commits:
   - **Commit 1 (Pre-Release Version Bump & Tag):** Update version strings in `native/credentio_c.h`, `native/credentio_c.cc`, `python/pyproject.toml`, `python/src/credentio/__init__.py`, `python/src/credentio/signer.py`, `go/cmd/credentio/main.go`, `go/signer.go`, `swift/Sources/credentio-cli/CredentioCLI.swift`, `swift/Sources/CredentioKit/Engines/CredentioSigner.swift`, `wasm/package.json` (plus `cd wasm && npm install --package-lock-only`), `wasm/src/signer.ts`, and documentation. Verify with `git grep -n "<prev_version>"` that only the 4 post-release asset-pinning files remain on `<prev_version>`. Keep `swift/Package.swift` and `scripts/fetch-prebuilt-lib.sh` pointing to the *previous* release until the new release finishes building. Commit, push `main`, and push tags `vX.Y.Z` and `go/vX.Y.Z` to trigger `.github/workflows/release.yml`.
   - **Commit 2 (Post-Release Asset Pinning):** Once `release.yml` publishes the `vX.Y.Z` assets, fetch `CredentioC.xcframework.zip.sha256` from the release and update `swift/Package.swift` (`releaseVersion` + `remoteChecksum`), `scripts/fetch-prebuilt-lib.sh`, `plugins/c2pa-inspector/skills/c2pa-inspect/scripts/fetch_native_lib.sh`, and `.github/workflows/ci.yml`.
5. **Upstream Commit Pinning, Local Checkout Sync & Drift Detection:**
   Build scripts source the authoritative commit from `.credentio-pin` (baseline: `ee4078badeea5739b0f0f246dbaea7803382718b`). Run `make check-drift` or trigger the scheduled `drift-check.yml` workflow to detect upstream movement on `refs/heads/main` prior to bumping the baseline. To inspect pending upstream Gerrit CLs before they merge, run `git ls-remote https://mediaprovenance.googlesource.com/credentio 'refs/changes/*'`. When working with a local sibling checkout at `../credentio`, keep `../credentio/bindings_c/` synced with `native/{credentio_c.h,credentio_c.cc,BUILD}`.
6. **Architecture Decisions:**
   Substantial architectural choices, FFI changes, or engine models must be recorded as Architecture Decision Records in `docs/adr/`.
7. **CGO Dynamic Linking and Runtime RPATH:**
   When working with CGo bindings on macOS (`darwin`), always ensure `-Wl,-rpath,${SRCDIR}/lib -Wl,-rpath,${SRCDIR}/../native` is defined in `#cgo darwin LDFLAGS`. macOS System Integrity Protection (SIP) sanitizes `DYLD_LIBRARY_PATH` across subprocesses, so embedded rpaths are required for downstream Go applications and tests to resolve `libcredentio_c.dylib` seamlessly. Ensure `CGO_ENABLED=1` is specified during builds and test executions.
8. **C2PA Manifest Schema & Format Resilience:**
   - **Five Lockstep `ParseCrJSON` Implementations:** Keep all five parsers synchronized: `go/models.go`, `python/src/credentio/models.py`, `swift/Sources/CredentioKit/Engines/CredentioCrjsonMapper.swift`, `wasm/src/parser.ts`, and `plugins/c2pa-inspector/skills/c2pa-inspect/scripts/inspect_c2pa.py`.
   - **Upstream `crJSON` Field Locations:** Upstream `ConvertToCrJson` (`utils/crjson.cc`) emits `specVersion` inside `manifests[i].validationResults.specVersion` and `manifests[i]["claim.v2"].specVersion` (not at the root JSON object), emits `dc:title` inside `claim.v2`, and uses camelCase `isUpdateManifest`. All parsers must check both root and per-manifest locations, accommodate C2PA v1 and v2 schemas (`claim` vs `claim.v2`, `certificateInfo.issuer.CN`, `validationResults` categorizing `success`, `failure`, and `informational`), and classify failure keywords (`not`, `invalid`, `mismatch`, `missing`, `untrusted`, `unsupported`, `malformed`, `revoked`, `expired`, `rejected`, `fail`, `error`) as `ERROR`.
   - **OOXML / ZIP Validation Routing:** Upstream `CreateZipFormat()` (`formats/zip/format.cc`) registers only the three OOXML MIME types (`.docx`, `.pptx`, `.xlsx`), not `"application/zip"`. In `native/credentio_c.cc`, never let `SniffMediaType` returning `"application/zip"` override `credentio::MediaType(file_path)`, and pass `std::nullopt` to `Validator::Validate` when the media type is `"application/zip"` so `FormatRegistry::GetFormat(reader)` resolves via `ZipAssessor::IsSupported(reader)`.
9. **Agent-Aware CLI Design:**
   CLI applications consuming these bindings should adhere to Agent-Aware standards: logical Cobra `GroupID` command categorization, structured `--json` output flags, proactive error hints, and semantic Lipgloss color palettes.
10. **C-ABI Surface & Emscripten Export Synchronization:**
    Whenever adding or modifying functions in `native/credentio_c.h` and `native/credentio_c.cc` (such as `cr_validator_*` or `cr_signer_*`), update all four locations in lockstep:
    - `native/credentio_c.h` & `native/credentio_c.cc`
    - `native/BUILD` (Bazel `deps`)
    - `scripts/build-wasm.sh` (both inline `BUILD` `deps` and the `-sEXPORTED_FUNCTIONS=[...]` array)
    - `python/src/credentio/_ffi.py` (`C_HEADER` cdef), `wasm/src/bridge/types.ts`, `go/`, and `swift/`
11. **Downstream Sibling Repositories (`../credentialctl` & `../credentio-validator-web`):**
    - **`../credentialctl`:** Consumes `github.com/ghchinoy/credentio-contributions/go@vX.Y.Z` and stages `libcredentio_c` via `./scripts/fetch-credentio-lib.sh` (also referenced in `.github/workflows/ci.yml` and `.github/workflows/release.yaml`).
    - **`../credentio-validator-web`:** Standalone browser validator hosted on Firebase Hosting (`generative-bazaar-001` / `https://credentio-validator.web.app`). Update its vendored WASM engine via `./scripts/update-engine.sh --release vX.Y.Z && npm run deploy`.
12. **Starlight Markdown Conventions & `npm ci` Lockfile Sync:**
    - Never include a top-level `# H1` in `docs-site/src/content/docs/*.{md,mdx}` body content because Starlight renders the frontmatter `title` as the page's `<h1>`.
    - When updating `docs-site/package.json` (especially with `"overrides"`), always run `cd docs-site && npm install && npm ci` locally before committing `package-lock.json` so GitHub Actions' `npm ci` step stays in sync.
