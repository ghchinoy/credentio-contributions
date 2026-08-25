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
	"sort"
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
		for i := range manifests {
			if manifests[i].Format == "" && mediaType != "" {
				manifests[i].Format = mediaType
			}
		}
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
	if !isUpdate {
		if iu, ok := dict["isUpdateManifest"].(bool); ok {
			isUpdate = iu
		}
	}

	claimDict, _ := dict["claim"].(map[string]interface{})
	if claimDict == nil {
		if c2, ok := dict["claim.v2"].(map[string]interface{}); ok {
			claimDict = c2
		} else {
			claimDict = make(map[string]interface{})
		}
	}

	// Generator extraction
	claimGenerator := ""
	if genObj, ok := claimDict["claim_generator_info"].(map[string]interface{}); ok {
		name, _ := genObj["name"].(string)
		ver, _ := genObj["version"].(string)
		claimGenerator = formatClaimGenerator(name, ver)
	} else if genList, ok := claimDict["claim_generator_info"].([]interface{}); ok && len(genList) > 0 {
		if first, ok := genList[0].(map[string]interface{}); ok {
			name, _ := first["name"].(string)
			ver, _ := first["version"].(string)
			claimGenerator = formatClaimGenerator(name, ver)
		}
	}
	if claimGenerator == "" {
		if genList, ok := dict["claim_generator_info"].([]interface{}); ok && len(genList) > 0 {
			if first, ok := genList[0].(map[string]interface{}); ok {
				name, _ := first["name"].(string)
				ver, _ := first["version"].(string)
				claimGenerator = formatClaimGenerator(name, ver)
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
	if sigDict == nil {
		if s, ok := dict["signature"].(map[string]interface{}); ok {
			sigDict = s
		}
	}
	if sigDict != nil {
		issuer, _ := sigDict["issuer"].(string)
		if issuer == "" {
			issuer, _ = sigDict["common_name"].(string)
		}
		if issuer == "" {
			if certInfo, ok := sigDict["certificateInfo"].(map[string]interface{}); ok {
				if issObj, ok := certInfo["issuer"].(map[string]interface{}); ok {
					if cn, ok := issObj["CN"].(string); ok {
						issuer = cn
					}
				}
			}
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
		} else if tsInfo, ok := sigDict["timeStampInfo"].(map[string]interface{}); ok {
			if timeStr, ok := tsInfo["timestamp"].(string); ok {
				if t, err := time.Parse(time.RFC3339, timeStr); err == nil {
					parsedTime = &t
				}
			}
		}
		certSummary, _ := sigDict["cert_serial_number"].(string)
		if certSummary == "" {
			if certInfo, ok := sigDict["certificateInfo"].(map[string]interface{}); ok {
				certSummary, _ = certInfo["serialNumber"].(string)
			}
		}
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
	if statusList == nil {
		if valResults, ok := dict["validationResults"].(map[string]interface{}); ok {
			for _, cat := range []string{"failure", "informational", "success"} {
				if catList, ok := valResults[cat].([]interface{}); ok {
					for _, item := range catList {
						if sDict, ok := item.(map[string]interface{}); ok {
							if code, ok := sDict["code"].(string); ok {
								exp, _ := sDict["explanation"].(string)
								url, _ := sDict["url"].(string)
								sev := classifySeverity(code)
								if cat == "failure" {
									sev = SeverityError
								} else if cat == "informational" || cat == "success" {
									sev = SeverityInfo
								}
								statuses = append(statuses, ValidationStatus{
									Code:        code,
									Explanation: exp,
									URL:         url,
									Severity:    sev,
								})
							}
						}
					}
				}
			}
		}
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
	dict, ok := value.(map[string]interface{})
	if !ok {
		return ""
	}

	// 1. Actions assertion
	if actions, ok := dict["actions"].([]interface{}); ok {
		var names []string
		for _, item := range actions {
			if aDict, ok := item.(map[string]interface{}); ok {
				if act, ok := aDict["action"].(string); ok {
					var extra string
					if dst, ok := aDict["digitalSourceType"].(string); ok && dst != "" {
						parts := strings.Split(dst, "/")
						extra = fmt.Sprintf(" (%s)", parts[len(parts)-1])
					} else if dst, ok := aDict["digital_source_type"].(string); ok && dst != "" {
						parts := strings.Split(dst, "/")
						extra = fmt.Sprintf(" (%s)", parts[len(parts)-1])
					}
					names = append(names, act+extra)
				}
			}
		}
		if len(names) > 0 {
			return strings.Join(names, ", ")
		}
	}

	// 2. Data hash assertion
	if hv, ok := dict["hash_value"].(string); ok {
		if len(hv) > 16 {
			return fmt.Sprintf("hash: %s…", hv[:16])
		}
		return fmt.Sprintf("hash: %s", hv)
	}

	// 3. AI Training and Mining assertion
	if strings.Contains(label, "training-mining") || strings.Contains(label, "data-mining") {
		if entries, ok := dict["entries"].(map[string]interface{}); ok {
			var formatted []string
			var keys []string
			for k := range entries {
				keys = append(keys, k)
			}
			sort.Strings(keys)
			for _, k := range keys {
				val := entries[k]
				shortKey := strings.TrimPrefix(strings.TrimPrefix(k, "c2pa."), "cawg.")
				if valDict, ok := val.(map[string]interface{}); ok {
					if use, ok := valDict["use"].(string); ok {
						formatted = append(formatted, fmt.Sprintf("%s=%s", shortKey, use))
					}
				} else if useStr, ok := val.(string); ok {
					formatted = append(formatted, fmt.Sprintf("%s=%s", shortKey, useStr))
				}
			}
			if len(formatted) > 0 {
				return fmt.Sprintf("AI Training: %s", strings.Join(formatted, ", "))
			}
		} else if use, ok := dict["use"].(string); ok {
			return fmt.Sprintf("AI Training: %s", use)
		}
	}

	// 4. Digital Source Type assertion
	if strings.Contains(label, "digital_source_type") || strings.Contains(label, "digitalSourceType") {
		typeVal, _ := dict["digital_source_type"].(string)
		if typeVal == "" {
			typeVal, _ = dict["digitalSourceType"].(string)
		}
		if typeVal == "" {
			typeVal, _ = dict["type"].(string)
		}
		if typeVal != "" {
			parts := strings.Split(typeVal, "/")
			return parts[len(parts)-1]
		}
	}

	// 5. AI Generative Info assertion
	if strings.Contains(label, "generative") || strings.Contains(label, "inference") {
		if modelDict, ok := dict["model"].(map[string]interface{}); ok {
			name, _ := modelDict["name"].(string)
			ver, _ := modelDict["version"].(string)
			if name != "" && ver != "" {
				return fmt.Sprintf("model: %s %s", name, ver)
			} else if name != "" {
				return fmt.Sprintf("model: %s", name)
			}
		}
		if modelName, ok := dict["model_name"].(string); ok {
			return fmt.Sprintf("model: %s", modelName)
		}
		if prompt, ok := dict["prompt"].(string); ok {
			return fmt.Sprintf("prompt: %s", prompt)
		}
	}

	return ""
}

func cleanGeneratorVersion(ver string) string {
	parts := strings.Split(ver, ":")
	if len(parts) == 2 && parts[0] != "" && parts[0] == parts[1] {
		return parts[0]
	}
	return ver
}

func formatClaimGenerator(name, ver string) string {
	cleanedVer := cleanGeneratorVersion(ver)
	if name != "" && cleanedVer != "" {
		return fmt.Sprintf("%s %s", name, cleanedVer)
	}
	return name
}
