---
title: C2PA Core Concepts
description: An overview of C2PA Content Credentials, manifests, assertions, and trust management.
---

The **Coalition for Content Provenance and Authenticity (C2PA)** creates open technical standards for certifying the source, history, and modifications of digital content.

Credentio implements the C2PA specification (versions 2.2 and 2.4), evaluating both structural integrity and cryptographic authenticity.

---

## 1. Key Data Structures

```text
Asset File (e.g. photo.jpg, video.mp4)
 └── Manifest Store
      ├── Active Manifest (The most recent claim about the asset)
      │    ├── Claim (Instance ID, Claim Generator Info)
      │    ├── Signature (X.509 Certificate Chain, Timestamp)
      │    ├── Assertions (Actions, Metadata, Thumbnails, Hash)
      │    └── Validation Statuses (Status codes & Severities)
      └── Ingredient Manifests (Parent or source assets used during creation)
```

### Manifests
- **Active Manifest:** Represents the latest verifiable claim attached to the asset.
- **Ingredient Manifests:** Embedded or referenced manifests from source media used to compose the asset (e.g. an original photograph edited in a compositing tool).
- **Update Manifests:** Lightweight records that attach new claims (like rights or metadata) without re-signing the entire asset payload.

### Claims
A container detailing:
- `instanceID`: A unique identifier for the version of the asset.
- `claim_generator_info`: Identifies the software agent that created the manifest (e.g., `"Adobe Photoshop 25.0"` or `"CredentioCamera 1.4"`).
- `signature_info`: Cryptographic details regarding the signing entity.

### Assertions
Discrete facts attached to the manifest:
- **Actions (`c2pa.actions`):** What operations were performed (e.g., `c2pa.created`, `c2pa.cropped`, `c2pa.color_adjustments`).
- **Ingredients (`c2pa.ingredient`):** References to upstream source assets.
- **AI Disclosures (`c2pa.training-mining`):** Information regarding AI generation or data mining constraints.
- **Data Hashes (`c2pa.hash.data`):** Cryptographic byte hashes binding the claim to the asset bytes.
- **Thumbnails (`c2pa.thumbnail.*`):** Embedded visual previews of the asset at the time of signing.

### Validation Statuses
The validation engine evaluates the manifest and emits structured status codes:
- **`INFO` (Valid):** e.g., `claimSignature.validated`, `assertion.dataHash.match`.
- **`WARNING`:** Informational notices or non-fatal discrepancies.
- **`ERROR` (Invalid):** Cryptographic failures, hash mismatches, or revoked certificates (e.g., `claimSignature.invalid`, `assertion.dataHash.mismatch`).

---

## 2. Trust Anchors & Trust Lists

C2PA signatures use standard X.509 PKI certificates. By default, Credentio evaluates cryptographic and hash validity locally without external network anchors.

In production, validators check signatures against **Trust Anchor Lists**:
1. **Claim Signer Trust Anchors:** Root and intermediate PEM certificates authorized to sign C2PA claims.
2. **Time Stamping Authority (TSA) Trust Anchors:** Certificates for certified time-stamping authorities confirming signing time.

See the [Trust Anchors & Validity Guide](/credentio-contributions/trust/) for a deep dive on why signatures show as `untrusted` out of the box and how to configure custom roots.

---

## 3. Scope: Validation vs. Signing

Google Credentio and this repository focus specifically on **high-performance local validation and inspection** of existing C2PA credentials.

- **Validation (This Repository):** Reading, parsing, verifying cryptographic signatures, evaluating data hashes, and reporting granular provenance status.
- **Authoring & Signing (Out of Scope):** Creating new C2PA manifests, generating digital signatures, and embedding claims into media files. For authoring workflows, consult the upstream C2PA specification and signing tools.

---

## 4. Supported Media Formats

Credentio natively extracts and validates Content Credentials embedded within:

| Category | Extensions |
| :--- | :--- |
| **Image** | `.avif`, `.dng`, `.gif`, `.heic`, `.heif`, `.jpeg`, `.jpg`, `.png`, `.tif`, `.tiff`, `.webp` |
| **Video & Audio** | `.avi`, `.m4a`, `.mov`, `.mp3`, `.mp4`, `.wav`, `.flac` |
| **Document** | `.pdf`, `.docx`, `.pptx`, `.xlsx` |
