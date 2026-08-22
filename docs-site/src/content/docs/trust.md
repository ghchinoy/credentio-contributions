---
title: Trust Anchors & Validity
description: Understanding the difference between cryptographic validity and trust verification in C2PA Content Credentials.
---

When validating C2PA Content Credentials with Credentio, the validator answers two separate questions:

1. **Is the manifest cryptographically valid?** (Has the asset been modified since signing?)
2. **Do you trust the entity that signed it?** (Does the certificate chain to an authorized root?)

Understanding this distinction helps explain why newly validated media files often show as `untrusted` out of the box, and how to configure trust anchors for production systems.

---

## 1. Cryptographic Validity vs. Entity Trust

A C2PA manifest contains an embedded X.509 certificate and digital signature created by the camera, editing tool, or AI generation pipeline that produced the media.

- **Cryptographic Verification (Self-Contained):**
  The validator verifies that the internal byte hashes match the asset content and that the signature was created by the embedded certificate. This check requires only the asset itself. No external trust lists or network calls are needed.
- **Trust Verification (Requires Trust Anchors):**
  The validator checks whether the signer certificate chains to a recognized root Certificate Authority (CA) that you have chosen to trust. If the certificate is valid but does not link to a trusted anchor, Credentio reports `signingCredential.untrusted`.

An `untrusted` status does not mean the signature is broken or tampered with. It means the signature is intact, but the signer has not yet been vouched for in your configured trust store.

---

## 2. Why Are Credentials Untrusted by Default?

Unlike web browsers that ship with hundreds of pre-installed root certificates for HTTPS, C2PA tools do not bundle a universal default trust store.

As noted in Google Credentio's official documentation, the core validator intentionally does not distribute trust lists. When running with default settings or `--skip-trust-checks`, Credentio verifies cryptographic integrity while skipping trust evaluations.

---

## 3. Configuring Trust Anchors in Production

To verify that signatures come from recognized organizations, download the official C2PA trust lists:

1. **C2PA Claim Signer Trust List:** Contains certificates for conformant signing tools and hardware manufacturers (available from the [C2PA Conformance Repository](https://github.com/c2pa-org/conformance-public/tree/main/trust-list)).
2. **C2PA Timestamp Authority (TSA) Trust List:** Contains certificates for certified time-stamping authorities.

Once downloaded as PEM files, pass the paths directly to your validator:

### Command-Line Interface (CLI)
```bash
credentio validate photo.jpg \
  --claim-signer-trust=/path/to/claim_signer_roots.pem \
  --tsa-trust=/path/to/tsa_roots.pem
```

### Python
```python
from credentio import Validator

with open("claim_signer_roots.pem") as f:
    claim_roots = f.read()
with open("tsa_roots.pem") as f:
    tsa_roots = f.read()

validator = Validator(
    claim_signer_trust_pem=claim_roots,
    tsa_trust_pem=tsa_roots,
    skip_trust_checks=False
)
report = validator.validate_file("photo.jpg")
```

### Go
```go
claimPEM, _ := os.ReadFile("claim_signer_roots.pem")
tsaPEM, _ := os.ReadFile("tsa_roots.pem")

validator, _ := credentio.NewValidator(
    credentio.WithClaimSignerTrust(string(claimPEM)),
    credentio.WithTSATrust(string(tsaPEM)),
    credentio.WithSkipTrustChecks(false),
)
```

### Swift
```swift
let engine = CredentioNativeEngine(
    claimSignerTrustPath: "/path/to/claim_signer_roots.pem",
    tsaTrustPath: "/path/to/tsa_roots.pem",
    skipTrustChecks: false
)
```

---

## 4. Revocation and Timestamping (OCSP / TSA)

Beyond static root certificates, production validation can check online certificate revocation:

- **Online Certificate Status Protocol (OCSP):** Queries the certificate authority in real time to verify that the signer certificate was not revoked after issuance.
- **Time Stamping Authority (TSA):** Verifies that the embedded signature timestamp was attested by an independent RFC 3161 time authority when the file was signed.

While anchor verification reads a local PEM file with zero latency, live OCSP and TSA network lookups introduce small network round-trips.

---

## 5. Summary

| Verification Stage | Requirement | Network Call? | Outcome if Missing |
| :--- | :--- | :--- | :--- |
| **Tamper Detection** | Embedded Asset Manifest | No | `INVALID` |
| **Trust Evaluation** | Local Trust Anchor PEM | No | `UNTRUSTED` (Valid signature, unverified signer) |
| **Revocation Check** | OCSP Responder | Yes | Non-revoked status unconfirmed |
