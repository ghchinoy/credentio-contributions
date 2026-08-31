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
4ac69fc58256d3871e765f615254373e19e250e9
```

All build scripts (`scripts/build-shared-lib.sh`, `scripts/build-swift-xcframework.sh`, `scripts/build-wasm.sh`) and CI release workflows dynamically source this file when cloning upstream Credentio during automated builds.

You can override the pinned baseline locally by exporting the `CREDENTIO_SHA` environment variable:

```bash
export CREDENTIO_SHA="<custom_git_commit_sha>"
```

---

## 2. Checking for Upstream Drift

You can verify whether Google Credentio's `main` branch has advanced beyond the pinned baseline at any time:

```bash
make check-drift
```

Under the hood, `scripts/check-credentio-drift.sh` queries the upstream Git remote using `git ls-remote`:

- **In Sync (Exit code `0`):** Upstream `main` matches `.credentio-pin`.
- **Drift Detected (Exit code `1`):** Upstream `main` has new commits. The script prints the pinned SHA, the upstream SHA, and a direct GoogleSource log comparison URL (`https://mediaprovenance.googlesource.com/credentio/+log/<pinned>..<upstream>`).
- **Network Error (Exit code `2`):** Failed to query the remote repository.

---

## 3. Automated Weekly CI Tracking

The repository includes a scheduled GitHub Actions workflow (`.github/workflows/drift-check.yml`) that runs every Monday at 09:00 UTC (and on manual `workflow_dispatch`):

1. Executes `scripts/check-credentio-drift.sh`.
2. When drift is detected, the workflow idempotently opens or updates a tracking issue on GitHub labeled `upstream-drift`.
3. The tracking issue includes direct comparison links and step-by-step verification instructions.

---

## 4. Updating the Pinned Baseline

When upstream Credentio introduces new features or security updates, follow this validation cycle before bumping `.credentio-pin`:

### Step 1: Inspect Upstream Changes
Review the commit log between the current baseline and upstream `HEAD`:
```bash
make check-drift
```

### Step 2: Test All Language Bindings
Verify that native compilation and test suites pass against the new commit:
```bash
export CREDENTIO_SHA="<new_upstream_sha>"

# 1. Build and test Python
make python-test

# 2. Build and test Go
make go-test

# 3. Build and test Swift
make swift-test
```

### Step 3: Update `.credentio-pin`
Write the verified commit hash to `.credentio-pin`:
```bash
echo "<new_upstream_sha>" > .credentio-pin
```

Commit and push the updated baseline to GitHub.
