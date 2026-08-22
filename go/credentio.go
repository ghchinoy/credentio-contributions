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
#cgo darwin LDFLAGS: -L${SRCDIR}/lib -L${SRCDIR}/../native -lcredentio_c
#cgo linux LDFLAGS: -L${SRCDIR}/lib -L${SRCDIR}/../native -lcredentio_c -Wl,-rpath,${SRCDIR}/lib -Wl,-rpath,${SRCDIR}/../native
#include "credentio_c.h"
#include <stdlib.h>
*/
import "C"

import (
	"errors"
	"fmt"
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
