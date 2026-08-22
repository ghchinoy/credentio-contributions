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
