# Credentio Python Binding

High-performance Python bindings for [Google Credentio](https://mediaprovenance.googlesource.com/credentio/) C2PA Content Credentials validator.

## Installation

```bash
pip install credentio
```

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
