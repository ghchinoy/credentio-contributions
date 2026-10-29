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

import (
	"bytes"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const sampleCrJSON = `
{
    "manifests": [
        {
            "label": "urn:c2pa:go_test_manifest",
            "title": "Authenticated Media in Go",
            "format": "image/jpeg",
            "claim": {
                "instanceID": "inst-go-100",
                "claim_generator_info": [
                    { "name": "GoCredentioAgent", "version": "3.1.0" }
                ],
                "signature_info": {
                    "issuer": "Google Trust Services",
                    "alg": "es256",
                    "time": "2026-08-21T18:00:00Z",
                    "cert_serial_number": "5566778899"
                }
            },
            "assertions": {
                "c2pa.actions": {
                    "actions": [
                        { "action": "c2pa.created" },
                        { "action": "c2pa.published" }
                    ]
                },
                "c2pa.hash.data": {
                    "hash_value": "b64'MTIzNDU2Nzg5MA=='"
                }
            },
            "validation": {
                "status": [
                    {
                        "code": "claimSignature.validated",
                        "explanation": "Claim signature is authentic and verified."
                    }
                ]
            }
        }
    ],
    "validation_results": {
        "spec_version": "2.2",
        "media_type": "image/jpeg"
    }
}
`

func TestParseCrJSON(t *testing.T) {
	report, err := ParseCrJSON(sampleCrJSON, "image/jpeg", 0.005, 0.003)
	if err != nil {
		t.Fatalf("unexpected error parsing crJSON: %v", err)
	}

	if !report.HasCredentials {
		t.Errorf("expected HasCredentials to be true")
	}
	if report.Badge() != BadgeSigned {
		t.Errorf("expected badge to be %q, got %q", BadgeSigned, report.Badge())
	}
	if report.SpecVersion != "2.2" {
		t.Errorf("expected SpecVersion to be '2.2', got %q", report.SpecVersion)
	}
	if report.ActiveManifest == nil {
		t.Fatalf("expected ActiveManifest not to be nil")
	}

	manifest := report.ActiveManifest
	if manifest.Label != "urn:c2pa:go_test_manifest" {
		t.Errorf("unexpected label: %s", manifest.Label)
	}
	if manifest.Title != "Authenticated Media in Go" {
		t.Errorf("unexpected title: %s", manifest.Title)
	}
	if manifest.ClaimGenerator != "GoCredentioAgent 3.1.0" {
		t.Errorf("unexpected claim generator: %s", manifest.ClaimGenerator)
	}
	if manifest.Signature == nil || manifest.Signature.Issuer != "Google Trust Services" {
		t.Errorf("unexpected signature issuer: %+v", manifest.Signature)
	}
	if len(manifest.Assertions) != 2 {
		t.Errorf("expected 2 assertions, got %d", len(manifest.Assertions))
	}
	if len(manifest.ValidationStatuses) != 1 {
		t.Errorf("expected 1 validation status, got %d", len(manifest.ValidationStatuses))
	}
	if manifest.ValidationStatuses[0].Severity != SeverityInfo {
		t.Errorf("expected severity info, got %s", manifest.ValidationStatuses[0].Severity)
	}
}

func TestParseCrJSON_V2SchemaAndToolkitFormat(t *testing.T) {
	const sampleV2JSON = `
	{
		"manifests": [
			{
				"label": "urn:uuid:google-c2pa-v2-sample",
				"title": "Google C2PA Core Generated Media",
				"format": "image/webp",
				"isUpdateManifest": false,
				"claim.v2": {
					"claim_generator_info": {
						"name": "Google C2PA Core Generator",
						"version": "2.1.0"
					},
					"signature_info": {
						"certificateInfo": {
							"issuer": {
								"CN": "Google C2PA Intermediate CA"
							},
							"serialNumber": "112233445566"
						},
						"timeStampInfo": {
							"timestamp": "2026-08-23T12:00:00Z"
						},
						"alg": "es256"
					}
				},
				"assertions": {
					"c2pa.actions.v2": {
						"actions": [
							{ "action": "c2pa.opened" }
						]
					}
				},
				"validationResults": {
					"success": [
						{
							"code": "claimSignature.validated",
							"explanation": "Signature verification succeeded."
						}
					],
					"informational": [
						{
							"code": "signingCredential.trusted",
							"explanation": "Certificate path is trusted."
						}
					]
				}
			}
		],
		"spec_version": "2.2"
	}
	`

	report, err := ParseCrJSON(sampleV2JSON, "image/webp", 0.004, 0.002)
	if err != nil {
		t.Fatalf("unexpected error parsing v2 crJSON: %v", err)
	}

	if !report.HasCredentials {
		t.Errorf("expected HasCredentials to be true")
	}
	if report.Badge() != BadgeSigned {
		t.Errorf("expected badge to be %q, got %q", BadgeSigned, report.Badge())
	}
	if report.ActiveManifest == nil {
		t.Fatalf("expected ActiveManifest not to be nil")
	}

	manifest := report.ActiveManifest
	if manifest.Label != "urn:uuid:google-c2pa-v2-sample" {
		t.Errorf("unexpected label: %s", manifest.Label)
	}
	if manifest.ClaimGenerator != "Google C2PA Core Generator 2.1.0" {
		t.Errorf("unexpected claim generator: %s", manifest.ClaimGenerator)
	}
	if manifest.Signature == nil {
		t.Fatalf("expected signature info not to be nil")
	}
	if manifest.Signature.Issuer != "Google C2PA Intermediate CA" {
		t.Errorf("unexpected issuer: %s", manifest.Signature.Issuer)
	}
	if manifest.Signature.CertChainSummary != "112233445566" {
		t.Errorf("unexpected serial number: %s", manifest.Signature.CertChainSummary)
	}
	if manifest.Signature.Time == nil {
		t.Errorf("expected timestamp to be parsed from timeStampInfo")
	}
	if len(manifest.ValidationStatuses) != 2 {
		t.Errorf("expected 2 validation statuses, got %d", len(manifest.ValidationStatuses))
	}
	for _, status := range manifest.ValidationStatuses {
		if status.Severity != SeverityInfo {
			t.Errorf("expected status %s to have info severity, got %s", status.Code, status.Severity)
		}
	}
}

func TestAssertionSummaries(t *testing.T) {
	const sampleJSON = `
	{
		"manifests": [
			{
				"label": "urn:c2pa:ai_sample",
				"assertions": {
					"c2pa.training-mining": {
						"entries": {
							"c2pa.ai_generative_training": { "use": "notAllowed" },
							"c2pa.data_mining": { "use": "notAllowed" }
						}
					},
					"c2pa.digital_source_type": {
						"digital_source_type": "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia"
					},
					"c2pa.ai_generative_info": {
						"model": {
							"name": "Imagen",
							"version": "3.0"
						}
					}
				}
			}
		]
	}
	`

	report, err := ParseCrJSON(sampleJSON, "image/jpeg", 0.0, 0.0)
	if err != nil {
		t.Fatalf("unexpected error parsing crJSON: %v", err)
	}

	if report.ActiveManifest == nil {
		t.Fatalf("expected ActiveManifest not to be nil")
	}

	active := report.ActiveManifest
	var trainingSummary, sourceSummary, aiInfoSummary string
	for _, a := range active.Assertions {
		if a.Label == "c2pa.training-mining" {
			trainingSummary = a.Summary
		} else if a.Label == "c2pa.digital_source_type" {
			sourceSummary = a.Summary
		} else if a.Label == "c2pa.ai_generative_info" {
			aiInfoSummary = a.Summary
		}
	}

	expectedTraining := "AI Training: ai_generative_training=notAllowed, data_mining=notAllowed"
	if trainingSummary != expectedTraining {
		t.Errorf("expected training summary %q, got %q", expectedTraining, trainingSummary)
	}

	expectedSource := "trainedAlgorithmicMedia"
	if sourceSummary != expectedSource {
		t.Errorf("expected source summary %q, got %q", expectedSource, sourceSummary)
	}

	expectedAI := "model: Imagen 3.0"
	if aiInfoSummary != expectedAI {
		t.Errorf("expected AI info summary %q, got %q", expectedAI, aiInfoSummary)
	}
}

func TestParseCrJSON_PortlandiaProbeMP4(t *testing.T) {
	const rawPayload = `
	{
		"@context": ["https://c2pa.org/crjson/crJSON.schema.json"],
		"jsonGenerator": {"name": "Google C2PA Toolkit", "version": "0.0.1"},
		"manifests": [
			{
				"label": "urn:c2pa:6e34afa9-5f49-dac3-93e2-41f4dc0fa78b",
				"isUpdateManifest": false,
				"isCompressedManifest": false,
				"claim.v2": {
					"claim_generator_info": {
						"name": "Google C2PA Core Generator Library",
						"version": "969395858:969395858"
					},
					"instanceID": "3c9d9b36-4893-30c3-1ddd-4ef455a89d10",
					"signature": "self#jumbf=c2pa.signature"
				},
				"signature": {
					"algorithm": "ES256",
					"certificateInfo": {
						"issuer": {
							"C": "US",
							"CN": "TESTING Google C2PA Qual Media Services ICA G1",
							"O": "TESTING Google LLC"
						},
						"serialNumber": "ac047db08d82cb69298367b6ade5c7a987b75f"
					},
					"timeStampInfo": {
						"timestamp": "2026-08-23T16:55:41+00:00"
					}
				},
				"assertions": {
					"c2pa.actions.v2": {
						"actions": [
							{
								"action": "c2pa.created",
								"digitalSourceType": "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia"
							},
							{
								"action": "c2pa.edited",
								"digitalSourceType": "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia"
							}
						]
					},
					"c2pa.hash.bmff.v3": {
						"alg": "sha256",
						"hash": "b64'OhHVqHoQ78L854774ttX0O4SxB+jvLUfiGHSu3WbDbI='"
					}
				},
				"validationResults": {
					"success": [
						{"code": "claimSignature.validated"},
						{"code": "assertion.bmffHash.match"}
					],
					"informational": [
						{"code": "signingCredential.trusted"}
					]
				}
			}
		]
	}
	`

	report, err := ParseCrJSON(rawPayload, "video/mp4", 0.012, 0.010)
	if err != nil {
		t.Fatalf("unexpected error parsing crJSON: %v", err)
	}

	if !report.HasCredentials {
		t.Errorf("expected HasCredentials to be true")
	}
	if report.Badge() != BadgeSigned {
		t.Errorf("expected badge to be %q, got %q", BadgeSigned, report.Badge())
	}

	guard := report.ActiveManifest
	if guard == nil {
		t.Fatalf("expected ActiveManifest not to be nil")
	}

	// Verify generator version deduplication (969395858:969395858 -> 969395858)
	expectedGen := "Google C2PA Core Generator Library 969395858"
	if guard.ClaimGenerator != expectedGen {
		t.Errorf("expected generator %q, got %q", expectedGen, guard.ClaimGenerator)
	}

	// Verify format fallback to report mediaType
	if guard.Format != "video/mp4" {
		t.Errorf("expected format 'video/mp4', got %q", guard.Format)
	}

	// Verify actions summary with digitalSourceType
	var actionsSummary string
	for _, a := range guard.Assertions {
		if a.Label == "c2pa.actions.v2" {
			actionsSummary = a.Summary
		}
	}
	expectedActions := "c2pa.created (trainedAlgorithmicMedia), c2pa.edited (trainedAlgorithmicMedia)"
	if actionsSummary != expectedActions {
		t.Errorf("expected actions summary %q, got %q", expectedActions, actionsSummary)
	}

	// Verify signer issuer
	if guard.Signature == nil || guard.Signature.Issuer != "TESTING Google C2PA Qual Media Services ICA G1" {
		t.Errorf("unexpected signature issuer: %+v", guard.Signature)
	}

	// Verify validation statuses count
	if len(guard.ValidationStatuses) != 3 {
		t.Errorf("expected 3 validation statuses, got %d", len(guard.ValidationStatuses))
	}
}

func TestParseCrJSON_UpstreamSpecVersionAndStatusCodes(t *testing.T) {
	const rawPayload = `
	{
		"@context": ["https://c2pa.org/crjson/crJSON.schema.json"],
		"jsonGenerator": {"name": "Google C2PA Toolkit", "version": "0.0.1"},
		"manifests": [
			{
				"label": "urn:c2pa:upstream-crjson-alignment",
				"isUpdateManifest": true,
				"claim.v2": {
					"dc:title": "OOXML Signed Presentation",
					"specVersion": "2.2",
					"claim_generator_info": {
						"name": "CredentioOffice",
						"version": "1.0.0"
					}
				},
				"validation": {
					"status": [
						{
							"code": "algorithm.unsupported",
							"explanation": "Signature algorithm is not supported."
						}
					]
				},
				"validationResults": {
					"specVersion": "2.2"
				}
			}
		]
	}
	`
	report, err := ParseCrJSON(
		rawPayload,
		"application/vnd.openxmlformats-officedocument.presentationml.presentation",
		0.004,
		0.002,
	)
	if err != nil {
		t.Fatalf("unexpected error parsing crJSON: %v", err)
	}
	if !report.HasCredentials {
		t.Fatalf("expected HasCredentials to be true")
	}
	if report.SpecVersion != "2.2" {
		t.Errorf("expected SpecVersion '2.2', got %q", report.SpecVersion)
	}
	if report.Badge() != BadgeInvalid {
		t.Errorf("expected BadgeInvalid for algorithm.unsupported, got %q", report.Badge())
	}
	active := report.ActiveManifest
	if active == nil {
		t.Fatalf("expected ActiveManifest not to be nil")
	}
	if active.Title != "OOXML Signed Presentation" {
		t.Errorf("expected Title 'OOXML Signed Presentation', got %q", active.Title)
	}
	if !active.IsUpdateManifest {
		t.Errorf("expected IsUpdateManifest to be true")
	}
	if len(active.ValidationStatuses) != 1 || active.ValidationStatuses[0].Severity != SeverityError {
		t.Errorf("expected algorithm.unsupported to have SeverityError, got %+v", active.ValidationStatuses)
	}
}

func TestSniffMediaType(t *testing.T) {
	tests := []struct {
		header   []byte
		expected string
	}{
		{[]byte("ID3\x03\x00\x00\x00\x00;jGEOB"), "audio/mpeg"},
		{[]byte("fLaC\x00\x00\x00\""), "audio/flac"},
		{[]byte("RIFF\x24\x08\x00\x00WAVEfmt "), "audio/wav"},
		{[]byte("\xff\xd8\xff\xe0\x00\x10JFIF"), "image/jpeg"},
		{[]byte("\x89PNG\r\n\x1a\n\x00\x00"), "image/png"},
		{[]byte("%PDF-1.7"), "application/pdf"},
		{[]byte("\x00\x00\x00\x1cftypavif\x00\x00\x00\x00"), "image/avif"},
		{[]byte("\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00"), "video/mp4"},
	}

	for _, tc := range tests {
		got := SniffMediaType(tc.header)
		if got != tc.expected {
			t.Errorf("SniffMediaType(%q) = %q; want %q", tc.header, got, tc.expected)
		}
	}
}

func createSamplePNGBytes(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 16, 16))
	for y := 0; y < 16; y++ {
		for x := 0; x < 16; x++ {
			img.Set(x, y, color.RGBA{R: 40, G: 120, B: 220, A: 255})
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatalf("failed to encode sample PNG: %v", err)
	}
	return buf.Bytes()
}

func createSampleJPEGBytes(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 16, 16))
	for y := 0; y < 16; y++ {
		for x := 0; x < 16; x++ {
			img.Set(x, y, color.RGBA{R: 220, G: 80, B: 40, A: 255})
		}
	}
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 90}); err != nil {
		t.Fatalf("failed to encode sample JPEG: %v", err)
	}
	return buf.Bytes()
}

func TestSignAndValidateBytes_RoundTrip(t *testing.T) {
	pki, err := GenerateTestPKI("Credentio Go Test")
	if err != nil {
		t.Fatalf("GenerateTestPKI failed: %v", err)
	}

	signer, err := NewSigner(
		pki.ClaimSignerKeyPEM,
		pki.ClaimSignerCertPEM,
		WithTSACredentials(pki.TSAKeyPEM, pki.TSACertPEM),
		WithGeneratorInfo("GoCredentioSigner", "0.2.0"),
	)
	if err != nil {
		t.Fatalf("NewSigner failed: %v", err)
	}
	defer signer.Close()

	rawPNG := createSamplePNGBytes(t)
	signRes, err := signer.SignBytes(rawPNG, &SignParams{
		MediaType:         "image/png",
		DigitalSourceType: DigitalSourceTypeDigitalCapture,
		CustomAssertions: map[string]any{
			"c2pa.training-mining": map[string]any{
				"entries": map[string]any{
					"c2pa.ai_generative_training": map[string]any{"use": "notAllowed"},
				},
			},
		},
	})
	if err != nil {
		t.Fatalf("SignBytes failed: %v", err)
	}
	if len(signRes.SignedBytes) <= len(rawPNG) {
		t.Fatalf("expected signed PNG (%d bytes) to be larger than source (%d bytes)", len(signRes.SignedBytes), len(rawPNG))
	}

	validator, err := NewValidator(
		WithClaimSignerTrust(pki.RootCACertPEM),
		WithTSATrust(pki.RootCACertPEM),
		WithSkipTrustChecks(false),
	)
	if err != nil {
		t.Fatalf("NewValidator failed: %v", err)
	}
	defer validator.Close()

	report, err := validator.ValidateBytes(signRes.SignedBytes, "image/png")
	if err != nil {
		t.Fatalf("ValidateBytes failed on signed PNG: %v", err)
	}

	if !report.HasCredentials {
		t.Fatalf("expected signed PNG to have credentials")
	}
	if report.Badge() != BadgeSigned {
		t.Fatalf("expected badge %q, got %q (statuses: %+v)", BadgeSigned, report.Badge(), report.ActiveManifest.ValidationStatuses)
	}
	if report.ActiveManifest == nil {
		t.Fatalf("expected ActiveManifest to be present")
	}
	if !strings.Contains(report.ActiveManifest.ClaimGenerator, "GoCredentioSigner") {
		t.Errorf("expected ClaimGenerator to contain 'GoCredentioSigner', got %q", report.ActiveManifest.ClaimGenerator)
	}
}

func TestSignAndValidateFile_RoundTrip(t *testing.T) {
	pki, err := GenerateTestPKI("Credentio File Test")
	if err != nil {
		t.Fatalf("GenerateTestPKI failed: %v", err)
	}

	tmpDir := t.TempDir()
	inPath := filepath.Join(tmpDir, "source.jpg")
	outPath := filepath.Join(tmpDir, "signed.jpg")

	if err := os.WriteFile(inPath, createSampleJPEGBytes(t), 0644); err != nil {
		t.Fatalf("failed to write input JPEG: %v", err)
	}

	signer, err := NewSigner(
		pki.ClaimSignerKeyPEM,
		pki.ClaimSignerCertPEM,
		WithGeneratorInfo("GoFileSigner", "0.2.0"),
	)
	if err != nil {
		t.Fatalf("NewSigner failed: %v", err)
	}
	defer signer.Close()

	signRes, err := signer.SignFile(inPath, outPath, &SignParams{
		DigitalSourceType: DigitalSourceTypeTrainedAlgorithmicMedia,
	})
	if err != nil {
		t.Fatalf("SignFile failed: %v", err)
	}
	if signRes.ByteSize == 0 {
		t.Errorf("expected non-zero output file size")
	}

	validator, err := NewValidator(WithSkipTrustChecks(true))
	if err != nil {
		t.Fatalf("NewValidator failed: %v", err)
	}
	defer validator.Close()

	report, err := validator.ValidateFile(outPath, "")
	if err != nil {
		t.Fatalf("ValidateFile failed: %v", err)
	}
	if !report.HasCredentials || report.Badge() != BadgeSigned {
		t.Fatalf("expected signed JPEG to validate as SIGNED, got badge=%s", report.Badge())
	}
}


