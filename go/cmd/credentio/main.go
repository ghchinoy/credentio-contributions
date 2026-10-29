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

const version = "0.2.2"

func printUsage() {
	fmt.Printf(`Usage: credentio <command> [options]

Google Credentio C2PA Content Credentials Command-Line Validator & Signer

Commands:
  validate <file_path>              Validate C2PA content credentials in a media asset
  sign <input_path> -o <out_path>   Embed and sign C2PA content credentials into a media asset
  keygen [-out-dir <dir>]           Generate a local C2PA test PKI (Root CA, Claim Signer, TSA)

Flags for validate:
  -json                  Output structured JSON
  -media-type <type>     Optional IANA media type (e.g. image/jpeg, video/mp4)
  -claim-signer-trust    Path to PEM file containing claim signer trust anchors
  -tsa-trust             Path to PEM file containing TSA trust anchors
  -skip-trust-checks     Skip certificate trust checks (default: true)

Flags for sign:
  -o, -output <path>     Output file path for signed asset (required)
  -key <pem_path>        Path to claim signer EC P-256 private key PEM (if omitted, uses ephemeral test PKI)
  -cert <pem_path>       Path to claim signer X.509 certificate chain PEM (if omitted, uses ephemeral test PKI)
  -tsa-key <pem_path>    Optional path to TSA EC P-256 private key PEM
  -tsa-cert <pem_path>   Optional path to TSA X.509 certificate PEM
  -source-type <uri>     Optional IPTC digitalSourceType URI (or 'capture', 'ai', 'composite-ai')
  -generator <name>      Generator software name (default: "Credentio CLI")
  -json                  Output structured JSON

Flags for keygen:
  -out-dir <dir>         Directory to write PEM files (default: "./test_pki")
  -org <name>            Organization name for X.509 subjects (default: "Credentio Test")
  -json                  Output structured JSON

Examples:
  credentio validate photo.jpg
  credentio keygen -out-dir ./test_pki
  credentio sign input.jpg -o signed.jpg -key ./test_pki/claim_signer_key.pem -cert ./test_pki/claim_signer_cert.pem
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
			gen = "-"
		}
		issuer := "-"
		if m.Signature != nil && m.Signature.Issuer != "" {
			issuer = m.Signature.Issuer
		}
		spec := report.SpecVersion
		if spec == "" {
			spec = "-"
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
		AssetPath           string               `json:"asset_path"`
		ByteSize            int64                `json:"byte_size"`
		MediaType           string               `json:"media_type"`
		EngineID            string               `json:"engine_id"`
		HasCredentials      bool                 `json:"has_credentials"`
		Badge               string               `json:"badge"`
		SpecVersion         string               `json:"spec_version,omitempty"`
		ElapsedSeconds      float64              `json:"elapsed_seconds"`
		CoreSeconds         float64              `json:"core_seconds,omitempty"`
		ActiveManifest      *credentio.Manifest  `json:"active_manifest,omitempty"`
		IngredientManifests []credentio.Manifest `json:"ingredient_manifests,omitempty"`
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

func resolveSourceTypeShorthand(v string) string {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "", "none":
		return ""
	case "capture", "digitalcapture":
		return credentio.DigitalSourceTypeDigitalCapture
	case "ai", "trainedalgorithmicmedia":
		return credentio.DigitalSourceTypeTrainedAlgorithmicMedia
	case "composite-ai":
		return credentio.DigitalSourceTypeCompositeWithTrainedAI
	default:
		return v
	}
}

func runKeygen(args []string) int {
	fs := flag.NewFlagSet("keygen", flag.ExitOnError)
	outDir := fs.String("out-dir", "./test_pki", "Output directory for generated PEM files")
	org := fs.String("org", "Credentio Test", "Organization name for X.509 certificate subjects")
	jsonOut := fs.Bool("json", false, "Output structured JSON")
	_ = fs.Parse(args)

	absDir, err := filepath.Abs(*outDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error resolving output directory: %v\n", err)
		return 3
	}

	pki, err := credentio.GenerateTestPKI(*org)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error generating test PKI: %v\n", err)
		return 3
	}

	if err := pki.WriteToDir(absDir); err != nil {
		fmt.Fprintf(os.Stderr, "Error writing PKI files: %v\n", err)
		return 3
	}

	if *jsonOut {
		payload := map[string]any{
			"output_dir":        absDir,
			"organization":      *org,
			"root_ca_cert":      filepath.Join(absDir, "root_ca_cert.pem"),
			"claim_signer_key":  filepath.Join(absDir, "claim_signer_key.pem"),
			"claim_signer_cert": filepath.Join(absDir, "claim_signer_cert.pem"),
			"tsa_key":           filepath.Join(absDir, "tsa_key.pem"),
			"tsa_cert":          filepath.Join(absDir, "tsa_cert.pem"),
		}
		b, _ := json.MarshalIndent(payload, "", "  ")
		fmt.Println(string(b))
		return 0
	}

	fmt.Printf("Generated C2PA test PKI in %s:\n", absDir)
	fmt.Printf("  Root CA Cert:      %s\n", filepath.Join(absDir, "root_ca_cert.pem"))
	fmt.Printf("  Claim Signer Key:  %s\n", filepath.Join(absDir, "claim_signer_key.pem"))
	fmt.Printf("  Claim Signer Cert: %s\n", filepath.Join(absDir, "claim_signer_cert.pem"))
	fmt.Printf("  TSA Key:           %s\n", filepath.Join(absDir, "tsa_key.pem"))
	fmt.Printf("  TSA Cert:          %s\n", filepath.Join(absDir, "tsa_cert.pem"))
	return 0
}

func runSign(args []string) int {
	fs := flag.NewFlagSet("sign", flag.ExitOnError)
	output := fs.String("output", "", "Output path for signed asset")
	outputShort := fs.String("o", "", "Output path for signed asset (shorthand)")
	keyPath := fs.String("key", "", "Path to claim signer EC P-256 private key PEM")
	certPath := fs.String("cert", "", "Path to claim signer X.509 certificate chain PEM")
	tsaKeyPath := fs.String("tsa-key", "", "Optional path to TSA EC P-256 private key PEM")
	tsaCertPath := fs.String("tsa-cert", "", "Optional path to TSA X.509 certificate PEM")
	mediaType := fs.String("media-type", "", "Optional IANA MIME type")
	sourceType := fs.String("source-type", "capture", "IPTC digitalSourceType URI or shorthand (capture, ai, composite-ai)")
	generator := fs.String("generator", "Credentio CLI", "Claim generator name")
	jsonOut := fs.Bool("json", false, "Output structured JSON")

	var positional []string
	var flagArgs []string
	for i := 0; i < len(args); i++ {
		if strings.HasPrefix(args[i], "-") {
			flagArgs = append(flagArgs, args[i])
			if i+1 < len(args) && !strings.HasPrefix(args[i+1], "-") && args[i] != "-json" && args[i] != "--json" {
				flagArgs = append(flagArgs, args[i+1])
				i++
			}
		} else {
			positional = append(positional, args[i])
		}
	}
	_ = fs.Parse(flagArgs)

	if len(positional) < 1 {
		fmt.Fprintln(os.Stderr, "Error: missing input asset file path to sign.")
		return 3
	}
	inputPath := positional[0]
	outPath := *output
	if outPath == "" {
		outPath = *outputShort
	}
	if outPath == "" {
		fmt.Fprintln(os.Stderr, "Error: -o / -output flag is required.")
		return 3
	}

	var keyPEM, certPEM, tsaKeyPEM, tsaCertPEM string
	if *keyPath != "" || *certPath != "" {
		if *keyPath == "" || *certPath == "" {
			fmt.Fprintln(os.Stderr, "Error: both -key and -cert must be provided together.")
			return 3
		}
		kb, err := os.ReadFile(*keyPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading claim signer key: %v\n", err)
			return 3
		}
		cb, err := os.ReadFile(*certPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error reading claim signer cert: %v\n", err)
			return 3
		}
		keyPEM = string(kb)
		certPEM = string(cb)
		if *tsaKeyPath != "" && *tsaCertPath != "" {
			tkb, err := os.ReadFile(*tsaKeyPath)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error reading TSA key: %v\n", err)
				return 3
			}
			tcb, err := os.ReadFile(*tsaCertPath)
			if err != nil {
				fmt.Fprintf(os.Stderr, "Error reading TSA cert: %v\n", err)
				return 3
			}
			tsaKeyPEM = string(tkb)
			tsaCertPEM = string(tcb)
		}
	} else {
		pki, err := credentio.GenerateTestPKI("Credentio CLI")
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error generating ephemeral test PKI: %v\n", err)
			return 3
		}
		keyPEM = pki.ClaimSignerKeyPEM
		certPEM = pki.ClaimSignerCertPEM
		tsaKeyPEM = pki.TSAKeyPEM
		tsaCertPEM = pki.TSACertPEM
	}

	var signerOpts []credentio.SignerOption
	signerOpts = append(signerOpts, credentio.WithGeneratorInfo(*generator, version))
	if tsaKeyPEM != "" && tsaCertPEM != "" {
		signerOpts = append(signerOpts, credentio.WithTSACredentials(tsaKeyPEM, tsaCertPEM))
	}

	signer, err := credentio.NewSigner(keyPEM, certPEM, signerOpts...)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error initializing signer: %v\n", err)
		return 3
	}
	defer signer.Close()

	res, err := signer.SignFile(inputPath, outPath, &credentio.SignParams{
		MediaType:         *mediaType,
		DigitalSourceType: resolveSourceTypeShorthand(*sourceType),
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Signing error: %v\n", err)
		return 3
	}

	if *jsonOut {
		b, _ := json.MarshalIndent(res, "", "  ")
		fmt.Println(string(b))
		return 0
	}

	fmt.Printf("Signed C2PA asset written to %s (%d bytes, core: %.2f ms)\n",
		res.OutputPath, res.ByteSize, res.CoreSeconds*1000.0)
	return 0
}

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(0)
	}

	switch os.Args[1] {
	case "-version", "--version":
		fmt.Printf("credentio version %s\n", version)
		os.Exit(0)
	case "keygen":
		os.Exit(runKeygen(os.Args[2:]))
	case "sign":
		os.Exit(runSign(os.Args[2:]))
	case "validate":
		// handled below
	default:
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
