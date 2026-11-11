---
title: Maintenance & Upstream Drift Detection
description: Baseline pinning, drift detection workflows, and scheduled CI tracking for Google Credentio.
---

Google Credentio is actively developed at `HEAD` on [Google's official repository](https://mediaprovenance.googlesource.com/credentio/).

To insulate downstream Python, Go, Swift, and WebAssembly applications from unexpected upstream schema or C++ API breaking changes, `credentio-contributions` maintains an authoritative, pinned baseline commit.

---

## 1. Authoritative Baseline (`.credentio-pin`)

The repository root contains a `.credentio-pin` file containing the validated commit hash:

```text
ee4078badeea5739b0f0f246dbaea7803382718b
```

All build scripts (`scripts/build-shared-lib.sh`, `scripts/build-swift-xcframework.sh`, `scripts/build-wasm.sh`) and CI release workflows dynamically source this file when cloning upstream Credentio during automated builds.

You can override the pinned baseline locally by exporting the `CREDENTIO_SHA` environment variable:

```bash
export CREDENTIO_SHA="<custom_git_commit_sha>"
```

---

## 2. Checking and Analyzing Upstream Drift

You can verify whether Google Credentio's `main` branch has advanced beyond the pinned baseline at any time:

```bash
make check-drift
```

Under the hood, `scripts/check-credentio-drift.sh` queries the upstream Git remote using `git ls-remote`:

- **In Sync (Exit code `0`):** Upstream `main` matches `.credentio-pin`.
- **Drift Detected (Exit code `1`):** Upstream `main` has new commits. The script prints the pinned SHA, the upstream SHA, and a direct GoogleSource log comparison URL (`https://mediaprovenance.googlesource.com/credentio/+log/<pinned>..<upstream>`).
- **Network Error (Exit code `2`):** Failed to query the remote repository.

To inspect both `refs/heads/main` and open Gerrit release CLs under `refs/changes/*`, classify changed files against our C-ABI headers (`native/credentio_c.cc`), and generate an upgrade recommendation tier (`NONE`, `SKIP_LOW`, `REBUILD_RECOMMENDED`, or `ABI_REVIEW_REQUIRED`), run:

```bash
make analyze-drift
```

`scripts/analyze-credentio-upstream.sh` also supports `--target <sha|ref>`, `--json`, and `--markdown` flags for automated agents and CI summaries.

---

## 3. Automated Weekly CI Tracking

The repository includes a scheduled GitHub Actions workflow (`.github/workflows/drift-check.yml`) that runs every Monday at 09:00 UTC (and on manual `workflow_dispatch` with an optional `target_ref` input):

1. Executes `scripts/check-credentio-drift.sh` and `scripts/analyze-credentio-upstream.sh`.
2. When drift is detected (or when a custom `target_ref` is dispatched), `verify-builds` compiles and tests Python, Go, Swift, and WebAssembly against the target commit on macOS.
3. For `main` branch drift, `report-drift` opens or updates a tracking issue on GitHub labeled `upstream-drift` containing the subsystem impact breakdown and 4-language build verification status.

---

## 4. Updating the Pinned Baseline

When upstream Credentio introduces new features or security updates, follow this validation cycle before bumping `.credentio-pin`:

### Step 1: Inspect Upstream Changes and Pending CLs
Run the impact analyzer to review the commit log, affected C-ABI headers, and recommendation tier:
```bash
make analyze-drift
```

### Step 2: Build and Test All Language Bindings
Verify that native compilation and test suites pass against the new commit across all four targets:
```bash
export CREDENTIO_SHA="<new_upstream_sha>"

# 1. Build C-ABI shared library and test Python & Go
make build-lib && make python-test && make go-test

# 2. Build static XCFramework and test Swift
make build-swift && make swift-test

# 3. Build WebAssembly engine and test TypeScript SDK
make build-wasm && make wasm-test
```

### Step 3: Update `.credentio-pin`
Write the verified commit hash to `.credentio-pin`:
```bash
echo "<new_upstream_sha>" > .credentio-pin
```

Commit and push the updated baseline to GitHub.
