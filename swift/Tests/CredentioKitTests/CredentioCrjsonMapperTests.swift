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
}
