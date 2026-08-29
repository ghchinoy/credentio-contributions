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
#cgo CFLAGS: -I${SRCDIR}/include -I${SRCDIR}/../native
#cgo darwin LDFLAGS: -L${SRCDIR}/lib -L${SRCDIR}/../native -lcredentio_c -Wl,-rpath,${SRCDIR}/lib -Wl,-rpath,${SRCDIR}/../native
#cgo linux LDFLAGS: -L${SRCDIR}/lib -L${SRCDIR}/../native -lcredentio_c -Wl,-rpath,${SRCDIR}/lib -Wl,-rpath,${SRCDIR}/../native
#include "credentio_c.h"
#include <stdlib.h>
*/
import "C"

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
	"unsafe"
)

// Validator represents an in-process Google Credentio C-ABI validator instance.
type Validator struct {
	ptr *C.cr_validator
	mu  sync.Mutex
}

type Option func(*validatorOptions)

type validatorOptions struct {
	claimSignerTrustPEM string
	tsaTrustPEM         string
	skipTrustChecks     bool
}

// WithClaimSignerTrust sets the PEM string containing claim signer trust anchors.
func WithClaimSignerTrust(pem string) Option {
	return func(o *validatorOptions) {
		o.claimSignerTrustPEM = pem
	}
}

// WithTSATrust sets the PEM string containing TSA trust anchors.
func WithTSATrust(pem string) Option {
	return func(o *validatorOptions) {
		o.tsaTrustPEM = pem
	}
}

// WithSkipTrustChecks sets whether to bypass certificate trust checks (useful for local verification).
func WithSkipTrustChecks(skip bool) Option {
	return func(o *validatorOptions) {
		o.skipTrustChecks = skip
	}
}

// NewValidator creates and initializes a new Credentio validator instance.
func NewValidator(opts ...Option) (*Validator, error) {
	config := validatorOptions{
		skipTrustChecks: true,
	}
	for _, opt := range opts {
		opt(&config)
	}

	var claimC *C.char
	if config.claimSignerTrustPEM != "" {
		claimC = C.CString(config.claimSignerTrustPEM)
		defer C.free(unsafe.Pointer(claimC))
	}

	var tsaC *C.char
	if config.tsaTrustPEM != "" {
		tsaC = C.CString(config.tsaTrustPEM)
		defer C.free(unsafe.Pointer(tsaC))
	}

	skipInt := C.int(0)
	if config.skipTrustChecks {
		skipInt = C.int(1)
	}

	ptr := C.cr_validator_create(claimC, tsaC, skipInt)
	if ptr == nil {
		return nil, errors.New("failed to initialize native Credentio validator")
	}

	return &Validator{ptr: ptr}, nil
}

// Close releases the underlying native C-ABI validator memory.
func (v *Validator) Close() error {
	v.mu.Lock()
	defer v.mu.Unlock()

	if v.ptr != nil {
		C.cr_validator_free(v.ptr)
		v.ptr = nil
	}
	return nil
}

// SniffMediaType inspects leading magic bytes to identify container MIME types.
func SniffMediaType(header []byte) string {
	if len(header) >= 3 && header[0] == 0x49 && header[1] == 0x44 && header[2] == 0x33 { // "ID3"
		return "audio/mpeg"
	}
	if len(header) >= 4 && string(header[:4]) == "fLaC" {
		return "audio/flac"
	}
	if len(header) >= 3 && header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF {
		return "image/jpeg"
	}
	if len(header) >= 8 && header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47 &&
		header[4] == 0x0D && header[5] == 0x0A && header[6] == 0x1A && header[7] == 0x0A {
		return "image/png"
	}
	if len(header) >= 6 && (string(header[:6]) == "GIF87a" || string(header[:6]) == "GIF89a") {
		return "image/gif"
	}
	if len(header) >= 4 && string(header[:4]) == "%PDF" {
		return "application/pdf"
	}
	if len(header) >= 12 && string(header[:4]) == "RIFF" {
		form := string(header[8:12])
		switch form {
		case "WAVE":
			return "audio/wav"
		case "WEBP":
			return "image/webp"
		case "AVI ":
			return "video/x-msvideo"
		}
	}
	if len(header) >= 12 && string(header[4:8]) == "ftyp" {
		brand := string(header[8:12])
		switch brand {
		case "avif", "avis":
			return "image/avif"
		case "heic", "heix", "mif1":
			return "image/heic"
		case "M4A ":
			return "audio/mp4"
		default:
			return "video/mp4"
		}
	}
	return ""
}

// ValidateFile validates an asset file on disk and returns its ProvenanceReport.
func (v *Validator) ValidateFile(filePath string, mediaType string) (*ProvenanceReport, error) {
	v.mu.Lock()
	defer v.mu.Unlock()

	if v.ptr == nil {
		return nil, errors.New("validator has been closed")
	}

	absPath, err := filepath.Abs(filePath)
	if err != nil {
		return nil, fmt.Errorf("invalid file path: %w", err)
	}

	if mediaType == "" {
		if f, err := os.Open(absPath); err == nil {
			header := make([]byte, 32)
			n, _ := f.Read(header)
			_ = f.Close()
			if n >= 4 {
				mediaType = SniffMediaType(header[:n])
			}
		}
	}

	pathC := C.CString(absPath)
	defer C.free(unsafe.Pointer(pathC))

	var mediaTypeC *C.char
	if mediaType != "" {
		mediaTypeC = C.CString(mediaType)
		defer C.free(unsafe.Pointer(mediaTypeC))
	}

	var outStatus C.int
	startTime := time.Now()
	jsonPtr := C.cr_validate_file(v.ptr, pathC, mediaTypeC, &outStatus)
	elapsedSeconds := time.Since(startTime).Seconds()
	coreSeconds := float64(C.cr_last_internal_seconds(v.ptr))

	status := int(outStatus)
	if jsonPtr == nil || status == C.CR_STATUS_NO_CREDENTIALS {
		if jsonPtr != nil {
			C.cr_string_free(jsonPtr)
		}
		return &ProvenanceReport{
			EngineID:       "credentio",
			EngineName:     "Credentio (Google)",
			HasCredentials: false,
			ElapsedSeconds: elapsedSeconds,
			CoreSeconds:    coreSeconds,
			MediaType:      mediaType,
		}, nil
	}

	if status != C.CR_STATUS_OK {
		errMsg := C.GoString(C.cr_last_error(v.ptr))
		if jsonPtr != nil {
			C.cr_string_free(jsonPtr)
		}
		return nil, fmt.Errorf("credentio validation failed (status %d): %s", status, errMsg)
	}

	rawJSON := C.GoString(jsonPtr)
	C.cr_string_free(jsonPtr)

	return ParseCrJSON(rawJSON, mediaType, elapsedSeconds, coreSeconds)
}

// ValidateBytes validates asset bytes in memory and returns its ProvenanceReport.
func (v *Validator) ValidateBytes(data []byte, mediaType string) (*ProvenanceReport, error) {
	v.mu.Lock()
	defer v.mu.Unlock()

	if v.ptr == nil {
		return nil, errors.New("validator has been closed")
	}
	if len(data) == 0 {
		return nil, errors.New("input data cannot be empty")
	}

	if mediaType == "" && len(data) >= 4 {
		limit := 32
		if len(data) < limit {
			limit = len(data)
		}
		mediaType = SniffMediaType(data[:limit])
	}

	var mediaTypeC *C.char
	if mediaType != "" {
		mediaTypeC = C.CString(mediaType)
		defer C.free(unsafe.Pointer(mediaTypeC))
	}

	var outStatus C.int
	bytesPtr := (*C.uint8_t)(unsafe.Pointer(&data[0]))
	dataLen := C.size_t(len(data))

	startTime := time.Now()
	jsonPtr := C.cr_validate_bytes(v.ptr, bytesPtr, dataLen, mediaTypeC, &outStatus)
	elapsedSeconds := time.Since(startTime).Seconds()
	coreSeconds := float64(C.cr_last_internal_seconds(v.ptr))

	status := int(outStatus)
	if jsonPtr == nil || status == C.CR_STATUS_NO_CREDENTIALS {
		if jsonPtr != nil {
			C.cr_string_free(jsonPtr)
		}
		return &ProvenanceReport{
			EngineID:       "credentio",
			EngineName:     "Credentio (Google)",
			HasCredentials: false,
			ElapsedSeconds: elapsedSeconds,
			CoreSeconds:    coreSeconds,
			MediaType:      mediaType,
		}, nil
	}

	if status != C.CR_STATUS_OK {
		errMsg := C.GoString(C.cr_last_error(v.ptr))
		if jsonPtr != nil {
			C.cr_string_free(jsonPtr)
		}
		return nil, fmt.Errorf("credentio validation failed (status %d): %s", status, errMsg)
	}

	rawJSON := C.GoString(jsonPtr)
	C.cr_string_free(jsonPtr)

	return ParseCrJSON(rawJSON, mediaType, elapsedSeconds, coreSeconds)
}
