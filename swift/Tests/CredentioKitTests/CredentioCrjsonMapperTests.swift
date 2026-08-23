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

@testable import CredentioKit
import Foundation
import XCTest

final class CredentioCrjsonMapperTests: XCTestCase {

    func testSupportedFormatsMapping() {
        XCTAssertEqual(SupportedFormats.mediaType(for: URL(fileURLWithPath: "test.jpg")), "image/jpeg")
        XCTAssertEqual(SupportedFormats.mediaType(for: URL(fileURLWithPath: "test.PNG")), "image/png")
        XCTAssertEqual(SupportedFormats.mediaType(for: URL(fileURLWithPath: "video.mp4")), "video/mp4")
        XCTAssertEqual(SupportedFormats.mediaType(for: URL(fileURLWithPath: "audio.wav")), "audio/wav")
        XCTAssertEqual(SupportedFormats.mediaType(for: URL(fileURLWithPath: "doc.pdf")), "application/pdf")
        XCTAssertNil(SupportedFormats.mediaType(for: URL(fileURLWithPath: "unknown.xyz")))

        XCTAssertEqual(SupportedFormats.category(for: URL(fileURLWithPath: "test.webp")), .image)
        XCTAssertEqual(SupportedFormats.category(for: URL(fileURLWithPath: "sample.mov")), .video)
        XCTAssertEqual(SupportedFormats.category(for: URL(fileURLWithPath: "sample.mp3")), .audio)
        XCTAssertEqual(SupportedFormats.category(for: URL(fileURLWithPath: "file.docx")), .document)
    }

    func testCredentioCrjsonMapping() {
        let sampleCrjson = """
        {
            "manifests": [
                {
                    "label": "urn:c2pa:credentio_sample",
                    "title": "Credentio Authenticated Media",
                    "format": "image/jpeg",
                    "claim": {
                        "instanceID": "inst-swift-123",
                        "claim_generator_info": [
                            { "name": "CredentioCamera", "version": "2.0.1" }
                        ],
                        "signature_info": {
                            "issuer": "Google Trust Services",
                            "alg": "es256",
                            "time": "2026-08-21T08:30:00Z",
                            "cert_serial_number": "987654321"
                        }
                    },
                    "assertions": {
                        "c2pa.actions": {
                            "actions": [
                                { "action": "c2pa.color_adjustments" }
                            ]
                        },
                        "c2pa.hash.data": {
                            "hash_value": "b64'YWJjZGVmZ2hpams='"
                        }
                    },
                    "validation": {
                        "status": [
                            {
                                "code": "claimSignature.validated",
                                "explanation": "Claim signature passed verification."
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
        """

        let report = CredentioCrjsonMapper.mapReport(
            json: sampleCrjson,
            mediaType: "image/jpeg",
            elapsed: .milliseconds(5),
            engineInternalElapsed: .milliseconds(3),
            engineID: "credentio-native",
            engineName: "Credentio Native (In-Process)"
        )

        XCTAssertTrue(report.hasCredentials)
        XCTAssertEqual(report.engineID, "credentio-native")
        XCTAssertEqual(report.specVersion, "2.2")
        XCTAssertEqual(report.badge, .signed)
        XCTAssertEqual(report.engineInternalElapsed, .milliseconds(3))

        guard let active = report.activeManifest else {
            XCTFail("Missing active manifest")
            return
        }
        XCTAssertEqual(active.label, "urn:c2pa:credentio_sample")
        XCTAssertEqual(active.title, "Credentio Authenticated Media")
        XCTAssertEqual(active.claimGenerator, "CredentioCamera 2.0.1")
        XCTAssertEqual(active.signature?.issuer, "Google Trust Services")
        XCTAssertEqual(active.assertions.count, 2)

        let actions = active.assertions.first(where: { $0.kind == .actions })
        XCTAssertNotNil(actions)
        XCTAssertEqual(actions?.summary, "c2pa.color_adjustments")
    }

    func testC2paToolFormatMapping() {
        let sampleC2paToolJson = """
        {
            "active_manifest": "contentauth:urn:uuid:5a08e472-active",
            "manifests": {
                "contentauth:urn:uuid:5a08e472-ingredient": {
                    "label": "contentauth:urn:uuid:5a08e472-ingredient",
                    "title": "Source Ingredient Asset",
                    "format": "image/png"
                },
                "contentauth:urn:uuid:5a08e472-active": {
                    "label": "contentauth:urn:uuid:5a08e472-active",
                    "title": "Active Composite Asset",
                    "format": "image/jpeg",
                    "claim": {
                        "claim_generator": "c2patool 0.9.0",
                        "signature_info": {
                            "issuer": "Test Signer CA",
                            "alg": "es256"
                        }
                    }
                }
            },
            "validation_status": [
                {
                    "code": "claimSignature.validated",
                    "explanation": "Claim signature verified."
                }
            ]
        }
        """

        let report = CredentioCrjsonMapper.mapReport(
            json: sampleC2paToolJson,
            mediaType: "image/jpeg",
            elapsed: .milliseconds(8),
            engineID: "rust-cli",
            engineName: "c2patool (Rust CLI)"
        )

        XCTAssertTrue(report.hasCredentials)
        XCTAssertEqual(report.badge, .signed)
        XCTAssertEqual(report.activeManifest?.label, "contentauth:urn:uuid:5a08e472-active")
        XCTAssertEqual(report.activeManifest?.title, "Active Composite Asset")
        XCTAssertEqual(report.activeManifest?.claimGenerator, "c2patool 0.9.0")
        XCTAssertEqual(report.activeManifest?.signature?.issuer, "Test Signer CA")
        XCTAssertEqual(report.activeManifest?.validationStatuses.count, 1)
        XCTAssertEqual(report.activeManifest?.validationStatuses.first?.code, "claimSignature.validated")

        XCTAssertEqual(report.ingredientManifests.count, 1)
        XCTAssertEqual(report.ingredientManifests.first?.label, "contentauth:urn:uuid:5a08e472-ingredient")
    }

    func testValidationSeverityBadgeRollup() {
        let validStatus = ValidationStatus(code: "claimSignature.validated", severity: .info)
        let manifestOk = Manifest(label: "ok", validationStatuses: [validStatus])
        XCTAssertEqual(manifestOk.overallValidity, .signed)

        let invalidStatus = ValidationStatus(code: "assertion.dataHash.mismatch", severity: .error)
        let manifestBad = Manifest(label: "bad", validationStatuses: [validStatus, invalidStatus])
        XCTAssertEqual(manifestBad.overallValidity, .invalid)

        let reportSigned = ProvenanceReport(
            engineID: "test",
            engineName: "test",
            hasCredentials: true,
            elapsed: .zero,
            activeManifest: manifestOk
        )
        XCTAssertEqual(reportSigned.badge, .signed)

        let reportInvalid = ProvenanceReport(
            engineID: "test",
            engineName: "test",
            hasCredentials: true,
            elapsed: .zero,
            activeManifest: manifestBad
        )
        XCTAssertEqual(reportInvalid.badge, .invalid)
    }

    func testConvenienceAccessors() {
        let manifest = Manifest(
            label: "test_label",
            claimGenerator: "CameraAgent 1.0",
            signature: SignatureInfo(issuer: "Trusted Issuer")
        )

        let verifiedReport = ProvenanceReport(
            engineID: "credentio",
            engineName: "Credentio",
            hasCredentials: true,
            elapsed: .milliseconds(5),
            activeManifest: manifest
        )
        XCTAssertTrue(verifiedReport.isVerified)
        XCTAssertFalse(verifiedReport.isInvalid)
        XCTAssertEqual(verifiedReport.primaryClaimGenerator, "CameraAgent 1.0")
        XCTAssertEqual(verifiedReport.primarySignerIssuer, "Trusted Issuer")

        let invalidStatus = ValidationStatus(code: "signature.invalid", severity: .error)
        let invalidManifest = Manifest(label: "invalid", validationStatuses: [invalidStatus])
        let invalidReport = ProvenanceReport(
            engineID: "credentio",
            engineName: "Credentio",
            hasCredentials: true,
            elapsed: .milliseconds(5),
            activeManifest: invalidManifest
        )
        XCTAssertFalse(invalidReport.isVerified)
        XCTAssertTrue(invalidReport.isInvalid)
    }

    func testAssertionSummaries() {
        let sampleJson = """
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
        """

        let report = CredentioCrjsonMapper.mapReport(
            json: sampleJson,
            mediaType: "image/jpeg",
            elapsed: .zero
        )

        guard let active = report.activeManifest else {
            XCTFail("Missing active manifest")
            return
        }

        let training = active.assertions.first(where: { $0.label == "c2pa.training-mining" })
        XCTAssertEqual(training?.summary, "AI Training: ai_generative_training=notAllowed, data_mining=notAllowed")

        let source = active.assertions.first(where: { $0.label == "c2pa.digital_source_type" })
        XCTAssertEqual(source?.summary, "trainedAlgorithmicMedia")

        let aiInfo = active.assertions.first(where: { $0.label == "c2pa.ai_generative_info" })
        XCTAssertEqual(aiInfo?.summary, "model: Imagen 3.0")
    }
}
