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
					"instanceID": "3c9d9b36-4893-30c3-1ddd-4ef455a89d10"
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

