---
title: Python Binding Reference
description: API documentation and usage patterns for the credentio Python package.
---

The `credentio` Python package provides typed, in-process C2PA verification powered by Google Credentio via `cffi`.

---

## 1. The `Validator` Class

### `Validator(...)`
Initializes a new native validator instance. Instances can be reused across thousands of validation requests for maximum throughput.

```python
from credentio import Validator

# Basic initialization (skips trust checks for local testing)
validator = Validator(skip_trust_checks=True)

# Production initialization with custom trust anchor PEMs
with open("claim_signer_roots.pem") as f:
    claim_roots = f.read()
with open("tsa_roots.pem") as f:
    tsa_roots = f.read()

validator = Validator(
    claim_signer_trust_pem=claim_roots,
    tsa_trust_pem=tsa_roots,
    skip_trust_checks=False
)
```

### `validate_file(file_path, media_type=None)`
Validates an asset file directly on disk using a high-performance C file reader.

```python
report = validator.validate_file("document.pdf", media_type="application/pdf")
```

### `validate_bytes(data, media_type=None)`
Validates media asset bytes directly from memory without writing to disk.

```python
with open("image.jpg", "rb") as f:
    image_bytes = f.read()

report = validator.validate_bytes(image_bytes, media_type="image/jpeg")
```

### Context Manager Support
Using `with Validator() as v:` ensures native C memory is automatically freed upon exiting the block.

```python
with Validator() as v:
    report = v.validate_file("video.mov")
```

---

## 2. Data Models & Return Types

Validation methods return a `ProvenanceReport` dataclass:

```python
@dataclass
class ProvenanceReport:
    engine_id: str                   # "credentio"
    engine_name: str                 # "Credentio (Google)"
    has_credentials: bool            # True if any C2PA claim was present
    elapsed_seconds: float           # Total time spent (including FFI bridging)
    core_seconds: Optional[float]    # Engine-internal C++ validation time
    media_type: Optional[str]        # IANA MIME type (e.g. "image/jpeg")
    spec_version: Optional[str]      # C2PA specification version (e.g. "2.2")
    active_manifest: Optional[Manifest]
    ingredient_manifests: List[Manifest]
    raw_json: Optional[str]          # Raw crJSON string returned by the C engine
```

### `Manifest`
```python
@dataclass
class Manifest:
    label: str
    title: Optional[str]
    format: Optional[str]
    claim_generator: Optional[str]
    is_update_manifest: bool
    signature: Optional[SignatureInfo]
    assertions: List[Assertion]
    validation_statuses: List[ValidationStatus]
    
    @property
    def overall_validity(self) -> BadgeState:
        # Returns BadgeState.INVALID if any status is Severity.ERROR, else BadgeState.SIGNED
```

### `SignatureInfo`
```python
@dataclass
class SignatureInfo:
    issuer: Optional[str]
    algorithm: Optional[str]
    time: Optional[datetime]
    cert_chain_summary: Optional[str]
```

### `Assertion`
```python
@dataclass
class Assertion:
    label: str
    kind: AssertionKind  # ACTIONS, INGREDIENT, THUMBNAIL, AI_TRAINING_MINING, METADATA, HASH, OTHER
    summary: Optional[str]
```

### `ValidationStatus`
```python
@dataclass
class ValidationStatus:
    code: str
    explanation: Optional[str]
    url: Optional[str]
    severity: Severity  # INFO, WARNING, ERROR
```

---

## 3. Error Handling

- **`CredentioLibraryNotFoundError`:** Raised on initial load if `libcredentio_c` shared library cannot be located.
- **`CredentioError`:** Raised if the native validator fails unrecoverably or is used after being closed.
- **`FileNotFoundError`:** Raised if the provided file path does not exist on disk.
