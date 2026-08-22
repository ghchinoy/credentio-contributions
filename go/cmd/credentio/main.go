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

package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/ghchinoy/credentio-contributions/go"
)

const version = "0.1.0"

func printUsage() {
	fmt.Printf(`Usage: credentio <command> [options]

Google Credentio C2PA Content Credentials Command-Line Validator

Commands:
  validate <file_path>   Validate C2PA content credentials in a media asset

Flags for validate:
  -json                  Output structured JSON
  -media-type <type>     Optional IANA media type (e.g. image/jpeg, video/mp4)
  -claim-signer-trust    Path to PEM file containing claim signer trust anchors
  -tsa-trust             Path to PEM file containing TSA trust anchors
  -skip-trust-checks     Skip certificate trust checks (default: true)
  -version               Show version information

Examples:
  credentio validate photo.jpg
  credentio validate video.mp4 -json
`)
}

func formatHumanOutput(report *credentio.ProvenanceReport, absPath string) string {
	fi, err := os.Stat(absPath)
	sizeMB := 0.0
	if err == nil {
		sizeMB = float64(fi.Size()) / (1024.0 * 1024.0)
	}

	var sb strings.Builder
	sb.WriteString(strings.Repeat("=", 64) + "\n")
	sb.WriteString("  Google Credentio C2PA Validation Report\n")
	sb.WriteString(strings.Repeat("=", 64) + "\n")
	sb.WriteString(fmt.Sprintf("Asset:       %s (%.2f MB, %s)\n", filepath.Base(absPath), sizeMB, report.MediaType))
	sb.WriteString(fmt.Sprintf("Path:        %s\n", absPath))
	sb.WriteString(fmt.Sprintf("Status:      %s\n", strings.ToUpper(string(report.Badge()))))

	if report.HasCredentials && report.ActiveManifest != nil {
		m := report.ActiveManifest
		gen := m.ClaimGenerator
		if gen == "" {
			gen = "—"
		}
		issuer := "—"
		if m.Signature != nil && m.Signature.Issuer != "" {
			issuer = m.Signature.Issuer
		}
		spec := report.SpecVersion
		if spec == "" {
			spec = "—"
		}
		sb.WriteString(fmt.Sprintf("Generator:   %s\n", gen))
		sb.WriteString(fmt.Sprintf("Signer:      %s\n", issuer))
		sb.WriteString(fmt.Sprintf("Format/Spec: %s (C2PA %s)\n", m.Format, spec))
		sb.WriteString(fmt.Sprintf("Assertions:  %d attached\n", len(m.Assertions)))
		sb.WriteString(fmt.Sprintf("Statuses:    %d reported\n", len(m.ValidationStatuses)))
	}

	if report.CoreSeconds > 0 {
		sb.WriteString(fmt.Sprintf("Core Time:   %.2f ms\n", report.CoreSeconds*1000.0))
	}
	sb.WriteString(fmt.Sprintf("Wall Time:   %.2f ms\n", report.ElapsedSeconds*1000.0))
	sb.WriteString(strings.Repeat("=", 64))
	return sb.String()
}

func formatJSONOutput(report *credentio.ProvenanceReport, absPath string) string {
	fi, _ := os.Stat(absPath)
	byteSize := int64(0)
	if fi != nil {
		byteSize = fi.Size()
	}

	type jsonOutput struct {
		AssetPath           string                     `json:"asset_path"`
		ByteSize            int64                      `json:"byte_size"`
		MediaType           string                     `json:"media_type"`
		EngineID            string                     `json:"engine_id"`
		HasCredentials      bool                       `json:"has_credentials"`
		Badge               string                     `json:"badge"`
		SpecVersion         string                     `json:"spec_version,omitempty"`
		ElapsedSeconds      float64                    `json:"elapsed_seconds"`
		CoreSeconds         float64                    `json:"core_seconds,omitempty"`
		ActiveManifest      *credentio.Manifest        `json:"active_manifest,omitempty"`
		IngredientManifests []credentio.Manifest       `json:"ingredient_manifests,omitempty"`
	}

	out := jsonOutput{
		AssetPath:           absPath,
		ByteSize:            byteSize,
		MediaType:           report.MediaType,
		EngineID:            report.EngineID,
		HasCredentials:      report.HasCredentials,
		Badge:               string(report.Badge()),
		SpecVersion:         report.SpecVersion,
		ElapsedSeconds:      report.ElapsedSeconds,
		CoreSeconds:         report.CoreSeconds,
		ActiveManifest:      report.ActiveManifest,
		IngredientManifests: report.IngredientManifests,
	}

	data, err := json.MarshalIndent(out, "", "  ")
	if err != nil {
		return "{}"
	}
	return string(data)
}

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(0)
	}

	if os.Args[1] == "-version" || os.Args[1] == "--version" {
		fmt.Printf("credentio version %s\n", version)
		os.Exit(0)
	}

	if os.Args[1] != "validate" {
		printUsage()
		os.Exit(0)
	}

	valFlags := flag.NewFlagSet("validate", flag.ExitOnError)
	jsonOutput := valFlags.Bool("json", false, "Output structured JSON")
	mediaType := valFlags.String("media-type", "", "Optional IANA MIME type")
	claimSignerTrust := valFlags.String("claim-signer-trust", "", "Path to claim signer trust anchors PEM")
	tsaTrust := valFlags.String("tsa-trust", "", "Path to TSA trust anchors PEM")
	skipTrust := valFlags.Bool("skip-trust-checks", true, "Skip trust anchor verification")

	valFlags.Parse(os.Args[2:])
	args := valFlags.Args()

	if len(args) < 1 {
		fmt.Fprintln(os.Stderr, "Error: missing asset file path to validate.")
		valFlags.Usage()
		os.Exit(3)
	}

	targetFile := args[0]
	absPath, err := filepath.Abs(targetFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error resolving path: %v\n", err)
		os.Exit(3)
	}

	if _, err := os.Stat(absPath); os.IsNotExist(err) {
		fmt.Fprintf(os.Stderr, "Error: file not found at %s\n", absPath)
		os.Exit(3)
	}

	var opts []credentio.Option
	if *claimSignerTrust != "" {
		pem, err := os.ReadFile(*claimSignerTrust)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading claim signer trust PEM: %v\n", err)
			os.Exit(3)
		}
		opts = append(opts, credentio.WithClaimSignerTrust(string(pem)))
		opts = append(opts, credentio.WithSkipTrustChecks(false))
	}
	if *tsaTrust != "" {
		pem, err := os.ReadFile(*tsaTrust)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading TSA trust PEM: %v\n", err)
			os.Exit(3)
		}
		opts = append(opts, credentio.WithTSATrust(string(pem)))
		opts = append(opts, credentio.WithSkipTrustChecks(false))
	}
	if *claimSignerTrust == "" && *tsaTrust == "" {
		opts = append(opts, credentio.WithSkipTrustChecks(*skipTrust))
	}

	validator, err := credentio.NewValidator(opts...)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error initializing validator: %v\n", err)
		os.Exit(3)
	}
	defer validator.Close()

	report, err := validator.ValidateFile(absPath, *mediaType)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Validation error: %v\n", err)
		os.Exit(3)
	}

	if *jsonOutput {
		fmt.Println(formatJSONOutput(report, absPath))
	} else {
		fmt.Println(formatHumanOutput(report, absPath))
	}

	switch report.Badge() {
	case credentio.BadgeSigned:
		os.Exit(0)
	case credentio.BadgeUnsigned:
		os.Exit(1)
	case credentio.BadgeInvalid:
		os.Exit(2)
	default:
		os.Exit(0)
	}
}
