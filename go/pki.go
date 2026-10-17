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
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha1"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/pem"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"time"
)

// TestPKI holds PEM-encoded keys and certificates conforming to the C2PA X.509 profile
// (C2PA claim signing EKU 1.3.6.1.4.1.62558.2.1 and RFC 3161 critical timeStamping EKU).
type TestPKI struct {
	RootCAKeyPEM       string `json:"root_ca_key_pem"`
	RootCACertPEM      string `json:"root_ca_cert_pem"`
	ClaimSignerKeyPEM  string `json:"claim_signer_key_pem"`
	ClaimSignerCertPEM string `json:"claim_signer_cert_pem"`
	TSAKeyPEM          string `json:"tsa_key_pem"`
	TSACertPEM         string `json:"tsa_cert_pem"`
}

// WriteToDir writes the generated PKI files (root_ca_key.pem, root_ca_cert.pem,
// claim_signer_key.pem, claim_signer_cert.pem, tsa_key.pem, tsa_cert.pem) into dir.
func (p *TestPKI) WriteToDir(dir string) error {
	if err := os.MkdirAll(dir, 0755); err != nil {
		return fmt.Errorf("failed to create PKI directory: %w", err)
	}
	files := map[string]struct {
		content string
		mode    os.FileMode
	}{
		"root_ca_key.pem":       {p.RootCAKeyPEM, 0600},
		"root_ca_cert.pem":      {p.RootCACertPEM, 0644},
		"claim_signer_key.pem":  {p.ClaimSignerKeyPEM, 0600},
		"claim_signer_cert.pem": {p.ClaimSignerCertPEM, 0644},
		"tsa_key.pem":           {p.TSAKeyPEM, 0600},
		"tsa_cert.pem":          {p.TSACertPEM, 0644},
	}
	for name, f := range files {
		target := filepath.Join(dir, name)
		if err := os.WriteFile(target, []byte(f.content), f.mode); err != nil {
			return fmt.Errorf("failed to write %s: %w", target, err)
		}
	}
	return nil
}

// GenerateTestPKI generates an in-memory C2PA-compliant Root CA, Claim Signer, and TSA key/certificate bundle
// using EC P-256 keys. Intended for local development, testing, and demonstration workflows.
func GenerateTestPKI(organization string) (*TestPKI, error) {
	if organization == "" {
		organization = "Credentio Test"
	}

	now := time.Now().UTC().Add(-5 * time.Minute)

	// 1. Root CA
	rootKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("failed to generate root CA key: %w", err)
	}
	rootKeyPEM, err := marshalPKCS8KeyPEM(rootKey)
	if err != nil {
		return nil, err
	}
	rootSKI, err := computeSubjectKeyID(&rootKey.PublicKey)
	if err != nil {
		return nil, err
	}
	rootSerial, err := randomSerial()
	if err != nil {
		return nil, err
	}

	rootTemplate := &x509.Certificate{
		SerialNumber: rootSerial,
		Subject: pkix.Name{
			Organization: []string{organization},
			CommonName:   organization + " Root CA",
		},
		NotBefore:             now,
		NotAfter:              now.Add(10 * 365 * 24 * time.Hour),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		BasicConstraintsValid: true,
		IsCA:                  true,
		SubjectKeyId:          rootSKI,
	}

	rootDER, err := x509.CreateCertificate(rand.Reader, rootTemplate, rootTemplate, &rootKey.PublicKey, rootKey)
	if err != nil {
		return nil, fmt.Errorf("failed to create root CA certificate: %w", err)
	}
	rootCert, err := x509.ParseCertificate(rootDER)
	if err != nil {
		return nil, err
	}
	rootCertPEM := string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: rootDER}))

	// 2. Claim Signer Leaf (C2PA Claim Signing EKU: 1.3.6.1.4.1.62558.2.1)
	claimKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("failed to generate claim signer key: %w", err)
	}
	claimKeyPEM, err := marshalPKCS8KeyPEM(claimKey)
	if err != nil {
		return nil, err
	}
	claimSKI, err := computeSubjectKeyID(&claimKey.PublicKey)
	if err != nil {
		return nil, err
	}
	claimSerial, err := randomSerial()
	if err != nil {
		return nil, err
	}

	c2paClaimSigningOID := asn1.ObjectIdentifier{1, 3, 6, 1, 4, 1, 62558, 2, 1}
	claimTemplate := &x509.Certificate{
		SerialNumber: claimSerial,
		Subject: pkix.Name{
			Organization: []string{organization},
			CommonName:   organization + " Claim Signer",
		},
		NotBefore:             now,
		NotAfter:              now.Add(365 * 24 * time.Hour),
		KeyUsage:              x509.KeyUsageDigitalSignature,
		UnknownExtKeyUsage:    []asn1.ObjectIdentifier{c2paClaimSigningOID},
		BasicConstraintsValid: true,
		IsCA:                  false,
		SubjectKeyId:          claimSKI,
		AuthorityKeyId:        rootSKI,
	}

	claimDER, err := x509.CreateCertificate(rand.Reader, claimTemplate, rootCert, &claimKey.PublicKey, rootKey)
	if err != nil {
		return nil, fmt.Errorf("failed to create claim signer certificate: %w", err)
	}
	claimCertPEM := string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: claimDER}))

	// 3. TSA Leaf (RFC 3161 requires critical timeStamping EKU: 1.3.6.1.5.5.7.3.8)
	tsaKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("failed to generate TSA key: %w", err)
	}
	tsaKeyPEM, err := marshalPKCS8KeyPEM(tsaKey)
	if err != nil {
		return nil, err
	}
	tsaSKI, err := computeSubjectKeyID(&tsaKey.PublicKey)
	if err != nil {
		return nil, err
	}
	tsaSerial, err := randomSerial()
	if err != nil {
		return nil, err
	}

	timeStampingOID := asn1.ObjectIdentifier{1, 3, 6, 1, 5, 5, 7, 3, 8}
	ekuBytes, err := asn1.Marshal([]asn1.ObjectIdentifier{timeStampingOID})
	if err != nil {
		return nil, err
	}

	tsaTemplate := &x509.Certificate{
		SerialNumber: tsaSerial,
		Subject: pkix.Name{
			Organization: []string{organization},
			CommonName:   organization + " TSA",
		},
		NotBefore:             now,
		NotAfter:              now.Add(365 * 24 * time.Hour),
		KeyUsage:              x509.KeyUsageDigitalSignature,
		BasicConstraintsValid: true,
		IsCA:                  false,
		SubjectKeyId:          tsaSKI,
		AuthorityKeyId:        rootSKI,
		ExtraExtensions: []pkix.Extension{
			{
				Id:       asn1.ObjectIdentifier{2, 5, 29, 37}, // id-ce-extKeyUsage
				Critical: true,
				Value:    ekuBytes,
			},
		},
	}

	tsaDER, err := x509.CreateCertificate(rand.Reader, tsaTemplate, rootCert, &tsaKey.PublicKey, rootKey)
	if err != nil {
		return nil, fmt.Errorf("failed to create TSA certificate: %w", err)
	}
	tsaCertPEM := string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: tsaDER}))

	return &TestPKI{
		RootCAKeyPEM:       rootKeyPEM,
		RootCACertPEM:      rootCertPEM,
		ClaimSignerKeyPEM:  claimKeyPEM,
		ClaimSignerCertPEM: claimCertPEM,
		TSAKeyPEM:          tsaKeyPEM,
		TSACertPEM:         tsaCertPEM,
	}, nil
}

func marshalPKCS8KeyPEM(key *ecdsa.PrivateKey) (string, error) {
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		return "", fmt.Errorf("failed to marshal PKCS#8 private key: %w", err)
	}
	return string(pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})), nil
}

func computeSubjectKeyID(pub *ecdsa.PublicKey) ([]byte, error) {
	spkiDER, err := x509.MarshalPKIXPublicKey(pub)
	if err != nil {
		return nil, err
	}
	var spki struct {
		Algorithm        pkix.AlgorithmIdentifier
		SubjectPublicKey asn1.BitString
	}
	if _, err := asn1.Unmarshal(spkiDER, &spki); err != nil {
		return nil, err
	}
	sum := sha1.Sum(spki.SubjectPublicKey.Bytes)
	return sum[:], nil
}

func randomSerial() (*big.Int, error) {
	limit := new(big.Int).Lsh(big.NewInt(1), 128)
	return rand.Int(rand.Reader, limit)
}
