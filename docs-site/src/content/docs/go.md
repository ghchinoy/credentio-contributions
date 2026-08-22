---
title: Go Package Reference
description: API documentation and usage patterns for the github.com/ghchinoy/credentio-contributions/go package.
---

The `github.com/ghchinoy/credentio-contributions/go` package provides native `cgo` bindings for Google Credentio.

---

## 1. The `Validator` Type

### `NewValidator(opts ...Option) (*Validator, error)`
Creates and initializes an in-process Credentio validator. `Validator` instances are protected by an internal mutex and are safe to call concurrently from multiple goroutines.

```go
import "github.com/ghchinoy/credentio-contributions/go"

// Initialize with test configuration
validator, err := credentio.NewValidator(
    credentio.WithSkipTrustChecks(true),
)
if err != nil {
    log.Fatalf("Failed to create validator: %v", err)
}
defer validator.Close()

// Initialize with production trust anchors
claimPEM, _ := os.ReadFile("claim_roots.pem")
tsaPEM, _ := os.ReadFile("tsa_roots.pem")

prodValidator, err := credentio.NewValidator(
    credentio.WithClaimSignerTrust(string(claimPEM)),
    credentio.WithTSATrust(string(tsaPEM)),
    credentio.WithSkipTrustChecks(false),
)
```

### `ValidateFile(filePath string, mediaType string) (*ProvenanceReport, error)`
Validates an asset file on disk. `mediaType` can be left empty `""` to infer the MIME type automatically from the file extension.

```go
report, err := validator.ValidateFile("media.mp4", "video/mp4")
if err != nil {
    log.Printf("Validation error: %v", err)
}
```

### `ValidateBytes(data []byte, mediaType string) (*ProvenanceReport, error)`
Validates media asset bytes directly in memory.

```go
fileBytes, _ := os.ReadFile("photo.webp")
report, err := validator.ValidateBytes(fileBytes, "image/webp")
```

### `Close() error`
Releases the underlying C-ABI validator memory.

---

## 2. Struct Definitions

### `ProvenanceReport`
```go
type ProvenanceReport struct {
	EngineID            string     `json:"engine_id"`
	EngineName          string     `json:"engine_name"`
	HasCredentials      bool       `json:"has_credentials"`
	ElapsedSeconds      float64    `json:"elapsed_seconds"`
	CoreSeconds         float64    `json:"core_seconds,omitempty"`
	MediaType           string     `json:"media_type,omitempty"`
	SpecVersion         string     `json:"spec_version,omitempty"`
	ActiveManifest      *Manifest  `json:"active_manifest,omitempty"`
	IngredientManifests []Manifest `json:"ingredient_manifests,omitempty"`
	RawJSON             string     `json:"raw_json,omitempty"`
}

func (r *ProvenanceReport) Badge() BadgeState // Returns BadgeSigned, BadgeUnsigned, or BadgeInvalid
```

### `Manifest`
```go
type Manifest struct {
	Label              string             `json:"label"`
	Title              string             `json:"title,omitempty"`
	Format             string             `json:"format,omitempty"`
	ClaimGenerator     string             `json:"claim_generator,omitempty"`
	IsUpdateManifest   bool               `json:"is_update_manifest"`
	Signature          *SignatureInfo     `json:"signature,omitempty"`
	Assertions         []Assertion        `json:"assertions,omitempty"`
	ValidationStatuses []ValidationStatus `json:"validation_statuses,omitempty"`
}
```

### `SignatureInfo`
```go
type SignatureInfo struct {
	Issuer           string     `json:"issuer,omitempty"`
	Algorithm        string     `json:"algorithm,omitempty"`
	Time             *time.Time `json:"time,omitempty"`
	CertChainSummary string     `json:"cert_chain_summary,omitempty"`
}
```

---

## 3. Standalone crJSON Parser

If you already have raw crJSON strings produced by Credentio's CLI (`c2pa_validate`) or another source, you can deserialize them into a typed `ProvenanceReport` without invoking `cgo`:

```go
report, err := credentio.ParseCrJSON(rawJSONString, "image/jpeg", 0.0, 0.0)
```
