# Credentio Python Binding

High-performance Python bindings for [Google Credentio](https://mediaprovenance.googlesource.com/credentio/) C2PA Content Credentials validator.

## Installation

Pre-compiled binary wheels with bundled native libraries (macOS arm64 and Linux x86_64) are available on [GitHub Releases](https://github.com/ghchinoy/credentio-contributions/releases):

```bash
# Download the matching wheel for your platform from GitHub Releases:
pip install https://github.com/ghchinoy/credentio-contributions/releases/download/v0.1.2/credentio-0.1.2-cp311-cp311-macosx_14_0_arm64.whl
```

> **Note:** Direct `pip install credentio` via PyPI is coming soon once Trusted Publishing is finalized.

## Quickstart

```python
from credentio import Validator

# 1. Create a validator instance (can be reused across multiple files)
with Validator() as validator:
    # 2. Validate a media file
    report = validator.validate_file("photo.jpg")

    if report.has_credentials:
        print(f"Status: {report.badge.value}")  # 'signed', 'unsigned', 'invalid'
        print(f"Claim Generator: {report.active_manifest.claim_generator}")
        print(f"Signer: {report.active_manifest.signature.issuer}")
        print(f"Validation time: {report.core_seconds * 1000:.2f} ms")
    else:
        print("No content credentials found.")
```
