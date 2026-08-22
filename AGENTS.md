# AGENTS.md: Contributor and Agent Guide

This document outlines the repository structure, common commands, and the documentation quality workflow for agents and developers working on `credentio-contributions`.

---

## 1. Project Overview and Structure

This repository provides native language bindings for [Google Credentio](https://mediaprovenance.googlesource.com/credentio/) built on a shared `extern "C"` Application Binary Interface (C-ABI):

- **`native/`**: The core C-ABI wrapper (`credentio_c.h`, `credentio_c.cc`, `BUILD`) and Clang modulemap.
- **`python/`**: Python package (`credentio`) using `cffi`, typed dataclasses, and CLI entry point.
- **`go/`**: Go package (`github.com/ghchinoy/credentio-contributions/go`) using `cgo` and standalone CLI.
- **`swift/`**: Standalone SwiftPM package (`CredentioKit`) with actor-isolated native engines and CLI.
- **`docs-site/`**: Interactive documentation portal built with [Astro Starlight](https://starlight.astro.build/) and the Catppuccin theme.
- **`docs/`**: Developer architecture guides and Architecture Decision Records (`docs/adr/`).
- **`scripts/`**: Automation scripts for building shared libraries and XCFrameworks via Bazel.

---

## 2. The Documentation and Quality Loop (TL;DR)

Whenever creating, updating, or reviewing documentation:

1. **Write or Edit Docs:**
   Update documentation pages under `docs-site/src/content/docs/`, guides under `docs/`, or language `README.md` files.
2. **Run Docstats and Editorial Linting:**
   Run the `technical-post-editorial` evaluation using `/workspace/docstats` to audit prose for house style, active voice, and plain language (target score: 9.0 to 10.0 / 10; hard floor >= 7.0). Ensure zero em dashes in prose.
3. **Score README Changes:**
   When writing or updating READMEs, evaluate against the Mark Allen quality rubric (`make-readme` skill; target score: >= 34 / 40, Excellent band).
4. **Verify Static Build:**
   Run `make docs-build` to ensure Astro Starlight generates all routes, search indexes (Pagefind), and site maps without broken references or link errors.
5. **Commit and Push Separately:**
   Stage files cleanly, create a concise descriptive commit, and verify with `git status` before pushing.

---

## 3. Running Docstats and Editorial Skills

The authoring tools live in `/workspace/docstats` and `/workspace/agent-skills/plugins/repo-authoring/skills/`:

### Run Docstats Scorecard on Documentation
```bash
uv run --directory /workspace/docstats python -c "
import sys
sys.path.insert(0, '/workspace/docstats')
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
- **Technical Post Editorial:** `/workspace/agent-skills/plugins/repo-authoring/skills/technical-post-editorial/SKILL.md`
- **Make README Rubric:** `/workspace/agent-skills/plugins/repo-authoring/skills/make-readme/SKILL.md`

---

## 4. Common Build and Test Commands

```bash
# Build native dynamic shared library (.dylib on macOS, .so on Linux for Python & Go):
make build-lib

# Build native static XCFramework (for Swift on macOS):
make build-swift

# Run test suites:
make python-test   # Run Python pytest suite
make go-test       # Run Go test suite
make swift-test    # Run Swift test suite
make test          # Run Python and Go test suites

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
4. **Distribution Reality:**
   Packages are currently source-distributed. Documentation examples must show build-from-source workflows (e.g. `make build-swift` followed by `.package(path: ...)`) rather than remote release tags until official releases are published.
5. **Upstream Commit Pinning:**
   Build scripts validate against commit `4ac69fc58256d3871e765f615254373e19e250e9`. Upstream Credentio changes should be verified prior to updating the baseline.
6. **Architecture Decisions:**
   Substantial architectural choices, FFI changes, or engine models must be recorded as Architecture Decision Records in `docs/adr/`.
