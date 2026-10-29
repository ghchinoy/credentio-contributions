# Credentio Python Binding

High-performance Python bindings for [Google Credentio](https://mediaprovenance.googlesource.com/credentio/) C2PA Content Credentials validator and signer.

> **Disclaimer:** This project is an open-source community contribution and is not an officially supported Google product.

## Installation

Pre-compiled binary wheels with bundled native libraries (macOS arm64 and Linux x86_64) are available on [GitHub Releases](https://github.com/ghchinoy/credentio-contributions/releases):

```bash
# Download the matching wheel for your platform from GitHub Releases:
pip install https://github.com/ghchinoy/credentio-contributions/releases/download/v0.2.2/credentio-0.2.2-cp311-cp311-macosx_11_0_arm64.whl
```

> **Note:** Direct `pip install credentio` via PyPI is coming soon once Trusted Publishing is finalized.

## Quickstart

### 1. Validate Media Assets

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

### 2. Sign Media Assets In-Process

```python
from credentio import Signer

with Signer(
    claim_signer_key_pem=key_pem,
    claim_signer_cert_pem=cert_pem,
    generator_name="MyPythonApp",
    generator_version="0.2.2",
) as signer:
    res = signer.sign_file(
        "input.png",
        "signed.png",
        digital_source_type="http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture",
        custom_assertions={
            "c2pa.training-mining": {
                "entries": {
                    "c2pa.ai_generative_training": {"use": "notAllowed"}
                }
            }
        },
    )
    print(f"Signed {res.byte_size} bytes in {res.core_seconds * 1000:.2f} ms")
```

### 3. Command-Line Interface

```bash
credentio validate photo.jpg [--json]
credentio sign input.png -o signed.png --key claim_signer_key.pem --cert claim_signer_cert.pem [--json]
```
