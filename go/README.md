# Credentio Go Binding (`github.com/ghchinoy/credentio-contributions/go`)

Idiomatic `cgo` bindings for [Google Credentio](https://mediaprovenance.googlesource.com/credentio/) C2PA Content Credentials validation and in-process signing.

> **Disclaimer:** This project is an open-source community contribution and is not an officially supported Google product.

---

## Installation

1. Add the Go module dependency:
   ```bash
   go get github.com/ghchinoy/credentio-contributions/go@v0.2.2
   ```
2. Stage the prebuilt `libcredentio_c` shared library (macOS arm64 / Linux x86_64) or compile from source:
   ```bash
   make fetch-lib   # or: make build-lib
   ```

---

## Quickstart

### 1. Validate Media Assets

```go
package main

import (
	"fmt"
	"log"

	"github.com/ghchinoy/credentio-contributions/go"
)

func main() {
	validator, err := credentio.NewValidator(credentio.WithSkipTrustChecks(true))
	if err != nil {
		log.Fatal(err)
	}
	defer validator.Close()

	report, err := validator.ValidateFile("photo.jpg", "")
	if err != nil {
		log.Fatal(err)
	}

	fmt.Printf("Badge: %s (Core: %.2f ms)\n", report.Badge(), report.CoreSeconds*1000)
}
```

### 2. Generate C2PA Test PKI & Sign Assets In-Process

```go
// Generate an EC P-256 test PKI (Root CA, Claim Signer with C2PA EKU, RFC 3161 TSA):
pki, err := credentio.GenerateTestPKI("My Studio")
if err != nil {
	log.Fatal(err)
}

signer, err := credentio.NewSigner(
	pki.ClaimSignerKeyPEM,
	pki.ClaimSignerCertPEM,
	credentio.WithTSACredentials(pki.TSAKeyPEM, pki.TSACertPEM),
	credentio.WithGeneratorInfo("MyGoService", "0.2.2"),
)
if err != nil {
	log.Fatal(err)
}
defer signer.Close()

res, err := signer.SignFile("input.png", "signed.png", &credentio.SignParams{
	DigitalSourceType: credentio.DigitalSourceTypeDigitalCapture,
})
```

---

## Command-Line Interface

```bash
cd go && CGO_ENABLED=1 go build -o ../bin/credentio ./cmd/credentio && cd ..

./bin/credentio keygen -out-dir ./test_pki
./bin/credentio sign input.png -o signed.png -key ./test_pki/claim_signer_key.pem -cert ./test_pki/claim_signer_cert.pem
./bin/credentio validate signed.png -json
```
