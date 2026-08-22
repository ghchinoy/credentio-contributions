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
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

type BadgeState string

const (
	BadgeSigned   BadgeState = "signed"
	BadgeUnsigned BadgeState = "unsigned"
	BadgeInvalid  BadgeState = "invalid"
)

type Severity string

const (
	SeverityInfo    Severity = "info"
	SeverityWarning Severity = "warning"
	SeverityError   Severity = "error"
)

type AssertionKind string

const (
	AssertionActions          AssertionKind = "actions"
	AssertionIngredient       AssertionKind = "ingredient"
	AssertionThumbnail        AssertionKind = "thumbnail"
	AssertionAITrainingMining AssertionKind = "ai_training_mining"
	AssertionMetadata         AssertionKind = "metadata"
	AssertionHash             AssertionKind = "hash"
	AssertionOther            AssertionKind = "other"
)

func ClassifyAssertion(label string) AssertionKind {
	lowered := strings.ToLower(label)
	if strings.Contains(lowered, "action") {
		return AssertionActions
	}
	if strings.Contains(lowered, "ingredient") {
		return AssertionIngredient
	}
	if strings.Contains(lowered, "thumbnail") {
		return AssertionThumbnail
	}
	if strings.Contains(lowered, "training-mining") || strings.Contains(lowered, "ai") {
		return AssertionAITrainingMining
	}
	if strings.Contains(lowered, "hash") {
		return AssertionHash
	}
	if strings.Contains(lowered, "metadata") || strings.Contains(lowered, "exif") || strings.Contains(lowered, "xmp") {
		return AssertionMetadata
	}
	return AssertionOther
}

type SignatureInfo struct {
	Issuer           string     `json:"issuer,omitempty"`
	Algorithm        string     `json:"algorithm,omitempty"`
	Time             *time.Time `json:"time,omitempty"`
	CertChainSummary string     `json:"cert_chain_summary,omitempty"`
}

type Assertion struct {
	Label   string        `json:"label"`
	Kind    AssertionKind `json:"kind"`
	Summary string        `json:"summary,omitempty"`
}

type ValidationStatus struct {
	Code        string   `json:"code"`
	Explanation string   `json:"explanation,omitempty"`
	URL         string   `json:"url,omitempty"`
	Severity    Severity `json:"severity"`
}

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

func (m *Manifest) OverallValidity() BadgeState {
	for _, s := range m.ValidationStatuses {
		if s.Severity == SeverityError {
			return BadgeInvalid
		}
	}
	return BadgeSigned
}

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

func (r *ProvenanceReport) Badge() BadgeState {
	if !r.HasCredentials || r.ActiveManifest == nil {
		if r.HasCredentials {
			return BadgeInvalid
		}
		return BadgeUnsigned
	}
	return r.ActiveManifest.OverallValidity()
}

func classifySeverity(code string) Severity {
	lowered := strings.ToLower(code)
	for _, keyword := range []string{"not", "invalid", "mismatch", "missing", "untrusted", "fail", "error"} {
		if strings.Contains(lowered, keyword) {
			return SeverityError
		}
	}
	for _, keyword := range []string{"validated", "trusted", "success", "ok"} {
		if strings.Contains(lowered, keyword) {
			return SeverityInfo
		}
	}
	return SeverityWarning
}

// ParseCrJSON maps a Credentio crJSON payload string into a typed ProvenanceReport.
func ParseCrJSON(rawJSON, mediaType string, elapsedSeconds, coreSeconds float64) (*ProvenanceReport, error) {
	var root map[string]interface{}
	if err := json.Unmarshal([]byte(rawJSON), &root); err != nil {
		return &ProvenanceReport{
			EngineID:       "credentio",
			EngineName:     "Credentio (Google)",
			HasCredentials: false,
			ElapsedSeconds: elapsedSeconds,
			CoreSeconds:    coreSeconds,
			MediaType:      mediaType,
			RawJSON:        rawJSON,
		}, nil
	}

	var manifests []Manifest

	if rawList, ok := root["manifests"].([]interface{}); ok {
		for i, item := range rawList {
			if mDict, ok := item.(map[string]interface{}); ok {
				manifests = append(manifests, mapManifest(mDict, fmt.Sprintf("manifest_%d", i)))
			}
		}
	} else if rawDict, ok := root["manifests"].(map[string]interface{}); ok {
		for label, item := range rawDict {
			if mDict, ok := item.(map[string]interface{}); ok {
				manifests = append(manifests, mapManifest(mDict, label))
			}
		}
	}

	var active *Manifest
	var ingredients []Manifest
	if len(manifests) > 0 {
		active = &manifests[0]
		if len(manifests) > 1 {
			ingredients = manifests[1:]
		}
	}

	specVersion := ""
	if sv, ok := root["spec_version"].(string); ok {
		specVersion = sv
	} else if vr, ok := root["validation_results"].(map[string]interface{}); ok {
		if sv, ok := vr["spec_version"].(string); ok {
			specVersion = sv
		} else if v, ok := vr["version"].(string); ok {
			specVersion = v
		}
	}

	return &ProvenanceReport{
		EngineID:            "credentio",
		EngineName:          "Credentio (Google)",
		HasCredentials:      active != nil,
		ElapsedSeconds:      elapsedSeconds,
		CoreSeconds:         coreSeconds,
		MediaType:           mediaType,
		SpecVersion:         specVersion,
		ActiveManifest:      active,
		IngredientManifests: ingredients,
		RawJSON:             rawJSON,
	}, nil
}

func mapManifest(dict map[string]interface{}, defaultLabel string) Manifest {
	label := defaultLabel
	if l, ok := dict["label"].(string); ok {
		label = l
	}
	title, _ := dict["title"].(string)
	format, _ := dict["format"].(string)
	isUpdate, _ := dict["is_update_manifest"].(bool)

	claimDict, _ := dict["claim"].(map[string]interface{})
	if claimDict == nil {
		claimDict = make(map[string]interface{})
	}

	// Generator extraction
	claimGenerator := ""
	genList, _ := claimDict["claim_generator_info"].([]interface{})
	if genList == nil {
		genList, _ = dict["claim_generator_info"].([]interface{})
	}
	if len(genList) > 0 {
		if first, ok := genList[0].(map[string]interface{}); ok {
			name, _ := first["name"].(string)
			ver, _ := first["version"].(string)
			if name != "" && ver != "" {
				claimGenerator = fmt.Sprintf("%s %s", name, ver)
			} else {
				claimGenerator = name
			}
		}
	}
	if claimGenerator == "" {
		if cg, ok := claimDict["claim_generator"].(string); ok {
			claimGenerator = cg
		} else if cg, ok := dict["claim_generator"].(string); ok {
			claimGenerator = cg
		}
	}

	// Signature
	var signature *SignatureInfo
	sigDict, _ := claimDict["signature_info"].(map[string]interface{})
	if sigDict == nil {
		sigDict, _ = dict["signature_info"].(map[string]interface{})
	}
	if sigDict != nil {
		issuer, _ := sigDict["issuer"].(string)
		if issuer == "" {
			issuer, _ = sigDict["common_name"].(string)
		}
		alg, _ := sigDict["alg"].(string)
		if alg == "" {
			alg, _ = sigDict["algorithm"].(string)
		}
		var parsedTime *time.Time
		if timeStr, ok := sigDict["time"].(string); ok {
			if t, err := time.Parse(time.RFC3339, timeStr); err == nil {
				parsedTime = &t
			}
		}
		certSummary, _ := sigDict["cert_serial_number"].(string)
		signature = &SignatureInfo{
			Issuer:           issuer,
			Algorithm:        alg,
			Time:             parsedTime,
			CertChainSummary: certSummary,
		}
	}

	// Assertions
	var assertions []Assertion
	if aDict, ok := dict["assertions"].(map[string]interface{}); ok {
		for aLabel, aVal := range aDict {
			assertions = append(assertions, Assertion{
				Label:   aLabel,
				Kind:    ClassifyAssertion(aLabel),
				Summary: summarizeAssertion(aLabel, aVal),
			})
		}
	}

	// Validation Statuses
	var statuses []ValidationStatus
	var statusList []interface{}
	if valObj, ok := dict["validation"].(map[string]interface{}); ok {
		statusList, _ = valObj["status"].([]interface{})
	}
	if statusList == nil {
		statusList, _ = dict["validation_status"].([]interface{})
	}
	for _, item := range statusList {
		if sDict, ok := item.(map[string]interface{}); ok {
			if code, ok := sDict["code"].(string); ok {
				exp, _ := sDict["explanation"].(string)
				url, _ := sDict["url"].(string)
				statuses = append(statuses, ValidationStatus{
					Code:        code,
					Explanation: exp,
					URL:         url,
					Severity:    classifySeverity(code),
				})
			}
		}
	}

	return Manifest{
		Label:              label,
		Title:              title,
		Format:             format,
		ClaimGenerator:     claimGenerator,
		IsUpdateManifest:   isUpdate,
		Signature:          signature,
		Assertions:         assertions,
		ValidationStatuses: statuses,
	}
}

func summarizeAssertion(label string, value interface{}) string {
	if dict, ok := value.(map[string]interface{}); ok {
		if actions, ok := dict["actions"].([]interface{}); ok {
			var names []string
			for _, item := range actions {
				if aDict, ok := item.(map[string]interface{}); ok {
					if act, ok := aDict["action"].(string); ok {
						names = append(names, act)
					}
				}
			}
			if len(names) > 0 {
				return strings.Join(names, ", ")
			}
		}
		if hv, ok := dict["hash_value"].(string); ok {
			if len(hv) > 16 {
				return fmt.Sprintf("hash: %s…", hv[:16])
			}
			return fmt.Sprintf("hash: %s", hv)
		}
	}
	return ""
}
