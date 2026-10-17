// Copyright 2026 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package credentio

/*
#include "credentio_c.h"
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
	"unsafe"
)

// Common IPTC Digital Source Type URIs used in C2PA Created/Edited actions.
const (
	DigitalSourceTypeDigitalCapture          = "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture"
	DigitalSourceTypeTrainedAlgorithmicMedia = "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia"
	DigitalSourceTypeCompositeWithTrainedAI  = "http://cv.iptc.org/newscodes/digitalsourcetype/compositeWithTrainedAlgorithmicMedia"
	DigitalSourceTypeAlgorithmicMedia        = "http://cv.iptc.org/newscodes/digitalsourcetype/algorithmicMedia"
	DigitalSourceTypeDigitalCreation         = "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCreation"
)

// Signer represents an in-process Google Credentio C-ABI manifest generator and asset signer.
type Signer struct {
	ptr *C.cr_signer
	mu  sync.Mutex
}

// SignerOption configures a Signer instance during creation.
type SignerOption func(*signerOptions)

type signerOptions struct {
	tsaKeyPEM        string
	tsaCertPEM       string
	generatorName    string
	generatorVersion string
}

// WithTSACredentials configures RFC 3161 timestamping credentials on the Signer.
func WithTSACredentials(tsaKeyPEM, tsaCertPEM string) SignerOption {
	return func(o *signerOptions) {
		o.tsaKeyPEM = tsaKeyPEM
		o.tsaCertPEM = tsaCertPEM
	}
}

// WithGeneratorInfo configures the claim_generator_info name and version embedded in signed manifests.
func WithGeneratorInfo(name, version string) SignerOption {
	return func(o *signerOptions) {
		o.generatorName = name
		o.generatorVersion = version
	}
}

// SignParams specifies per-asset options when signing a file or byte buffer.
type SignParams struct {
	// MediaType is the optional IANA MIME type (e.g., "image/jpeg"). If empty, inferred from magic bytes or extension.
	MediaType string
	// DigitalSourceType is the optional IPTC digital source type URI (e.g., DigitalSourceTypeDigitalCapture).
	DigitalSourceType string
	// CustomAssertions is an optional map of assertion labels (e.g., "c2pa.ai_generative_training") to JSON-serializable payloads.
	CustomAssertions map[string]any
	// CustomAssertionsJSON is an optional raw JSON string of custom assertions if pre-serialized.
	CustomAssertionsJSON string
}

// SignResult summarizes the outcome and timing of a signing operation.
type SignResult struct {
	OutputPath     string  `json:"output_path,omitempty"`
	SignedBytes    []byte  `json:"-"`
	ByteSize       int     `json:"byte_size"`
	MediaType      string  `json:"media_type,omitempty"`
	ElapsedSeconds float64 `json:"elapsed_seconds"`
	CoreSeconds    float64 `json:"core_seconds"`
}

// NewSigner creates and initializes a new native Credentio Signer from a PEM-encoded EC P-256 private key
// and PEM-encoded X.509 certificate chain (leaf first).
func NewSigner(claimSignerKeyPEM, claimSignerCertPEM string, opts ...SignerOption) (*Signer, error) {
	if claimSignerKeyPEM == "" || claimSignerCertPEM == "" {
		return nil, errors.New("claim signer private key PEM and certificate chain PEM are required")
	}

	cfg := signerOptions{
		generatorName:    "Credentio",
		generatorVersion: "0.2.0",
	}
	for _, opt := range opts {
		opt(&cfg)
	}

	keyC := C.CString(claimSignerKeyPEM)
	defer C.free(unsafe.Pointer(keyC))

	certC := C.CString(claimSignerCertPEM)
	defer C.free(unsafe.Pointer(certC))

	var tsaKeyC *C.char
	if cfg.tsaKeyPEM != "" {
		tsaKeyC = C.CString(cfg.tsaKeyPEM)
		defer C.free(unsafe.Pointer(tsaKeyC))
	}

	var tsaCertC *C.char
	if cfg.tsaCertPEM != "" {
		tsaCertC = C.CString(cfg.tsaCertPEM)
		defer C.free(unsafe.Pointer(tsaCertC))
	}

	genNameC := C.CString(cfg.generatorName)
	defer C.free(unsafe.Pointer(genNameC))

	genVerC := C.CString(cfg.generatorVersion)
	defer C.free(unsafe.Pointer(genVerC))

	ptr := C.cr_signer_create(keyC, certC, tsaKeyC, tsaCertC, genNameC, genVerC)
	if ptr == nil {
		return nil, errors.New("failed to initialize native Credentio signer (verify EC P-256 PKCS#8 key and certificate chain)")
	}

	return &Signer{ptr: ptr}, nil
}

// Close releases the underlying native C-ABI signer handle.
func (s *Signer) Close() error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.ptr != nil {
		C.cr_signer_free(s.ptr)
		s.ptr = nil
	}
	return nil
}

// SignFile embeds and signs a C2PA manifest into inputPath and writes the resulting signed asset to outputPath.
func (s *Signer) SignFile(inputPath, outputPath string, params *SignParams) (*SignResult, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.ptr == nil {
		return nil, errors.New("signer has been closed")
	}

	absIn, err := filepath.Abs(inputPath)
	if err != nil {
		return nil, fmt.Errorf("invalid input path: %w", err)
	}
	absOut, err := filepath.Abs(outputPath)
	if err != nil {
		return nil, fmt.Errorf("invalid output path: %w", err)
	}

	var p SignParams
	if params != nil {
		p = *params
	}

	mediaType := p.MediaType
	if mediaType == "" {
		if f, err := os.Open(absIn); err == nil {
			header := make([]byte, 32)
			n, _ := f.Read(header)
			_ = f.Close()
			if n >= 4 {
				mediaType = SniffMediaType(header[:n])
			}
		}
	}

	assertionsJSON, err := resolveAssertionsJSON(&p)
	if err != nil {
		return nil, err
	}

	inC := C.CString(absIn)
	defer C.free(unsafe.Pointer(inC))

	outC := C.CString(absOut)
	defer C.free(unsafe.Pointer(outC))

	var mediaTypeC *C.char
	if mediaType != "" {
		mediaTypeC = C.CString(mediaType)
		defer C.free(unsafe.Pointer(mediaTypeC))
	}

	var dstC *C.char
	if p.DigitalSourceType != "" {
		dstC = C.CString(p.DigitalSourceType)
		defer C.free(unsafe.Pointer(dstC))
	}

	var assertionsC *C.char
	if assertionsJSON != "" {
		assertionsC = C.CString(assertionsJSON)
		defer C.free(unsafe.Pointer(assertionsC))
	}

	startTime := time.Now()
	status := int(C.cr_sign_file(s.ptr, inC, outC, mediaTypeC, dstC, assertionsC))
	elapsedSeconds := time.Since(startTime).Seconds()
	coreSeconds := float64(C.cr_signer_last_internal_seconds(s.ptr))

	if status != C.CR_STATUS_OK {
		errMsg := C.GoString(C.cr_signer_last_error(s.ptr))
		return nil, fmt.Errorf("credentio signing failed (status %d): %s", status, errMsg)
	}

	var outSize int
	if fi, err := os.Stat(absOut); err == nil {
		outSize = int(fi.Size())
	}

	return &SignResult{
		OutputPath:     absOut,
		ByteSize:       outSize,
		MediaType:      mediaType,
		ElapsedSeconds: elapsedSeconds,
		CoreSeconds:    coreSeconds,
	}, nil
}

// SignBytes embeds and signs a C2PA manifest into an in-memory asset buffer and returns the signed bytes.
func (s *Signer) SignBytes(data []byte, params *SignParams) (*SignResult, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.ptr == nil {
		return nil, errors.New("signer has been closed")
	}
	if len(data) == 0 {
		return nil, errors.New("input data cannot be empty")
	}

	var p SignParams
	if params != nil {
		p = *params
	}

	mediaType := p.MediaType
	if mediaType == "" && len(data) >= 4 {
		limit := 32
		if len(data) < limit {
			limit = len(data)
		}
		mediaType = SniffMediaType(data[:limit])
	}

	assertionsJSON, err := resolveAssertionsJSON(&p)
	if err != nil {
		return nil, err
	}

	var mediaTypeC *C.char
	if mediaType != "" {
		mediaTypeC = C.CString(mediaType)
		defer C.free(unsafe.Pointer(mediaTypeC))
	}

	var dstC *C.char
	if p.DigitalSourceType != "" {
		dstC = C.CString(p.DigitalSourceType)
		defer C.free(unsafe.Pointer(dstC))
	}

	var assertionsC *C.char
	if assertionsJSON != "" {
		assertionsC = C.CString(assertionsJSON)
		defer C.free(unsafe.Pointer(assertionsC))
	}

	bytesPtr := (*C.uint8_t)(unsafe.Pointer(&data[0]))
	dataLen := C.size_t(len(data))
	var outSize C.size_t
	var outStatus C.int

	startTime := time.Now()
	signedPtr := C.cr_sign_bytes(
		s.ptr,
		bytesPtr,
		dataLen,
		mediaTypeC,
		dstC,
		assertionsC,
		&outSize,
		&outStatus,
	)
	elapsedSeconds := time.Since(startTime).Seconds()
	coreSeconds := float64(C.cr_signer_last_internal_seconds(s.ptr))

	status := int(outStatus)
	if signedPtr == nil || status != C.CR_STATUS_OK {
		errMsg := C.GoString(C.cr_signer_last_error(s.ptr))
		if signedPtr != nil {
			C.cr_bytes_free(signedPtr)
		}
		return nil, fmt.Errorf("credentio signing failed (status %d): %s", status, errMsg)
	}
	defer C.cr_bytes_free(signedPtr)

	signedBytes := C.GoBytes(unsafe.Pointer(signedPtr), C.int(outSize))

	return &SignResult{
		SignedBytes:    signedBytes,
		ByteSize:       len(signedBytes),
		MediaType:      mediaType,
		ElapsedSeconds: elapsedSeconds,
		CoreSeconds:    coreSeconds,
	}, nil
}

func resolveAssertionsJSON(p *SignParams) (string, error) {
	if p.CustomAssertionsJSON != "" {
		return p.CustomAssertionsJSON, nil
	}
	if len(p.CustomAssertions) > 0 {
		raw, err := json.Marshal(p.CustomAssertions)
		if err != nil {
			return "", fmt.Errorf("failed to marshal CustomAssertions: %w", err)
		}
		return string(raw), nil
	}
	return "", nil
}
