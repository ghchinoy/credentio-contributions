# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import json
import pytest
from credentio import (
    BadgeState,
    AssertionKind,
    Severity,
    parse_crjson,
)
from credentio._ffi import _find_library_path

SAMPLE_CRJSON = """
{
    "manifests": [
        {
            "label": "urn:c2pa:test_manifest",
            "title": "Authenticated Video Sample",
            "format": "video/mp4",
            "claim": {
                "instanceID": "inst-9999",
                "claim_generator_info": [
                    { "name": "CredentioCamera", "version": "1.4.2" }
                ],
                "signature_info": {
                    "issuer": "Google Trust Services LLC",
                    "alg": "es256",
                    "time": "2026-08-21T14:30:00Z",
                    "cert_serial_number": "1122334455"
                }
            },
            "assertions": {
                "c2pa.actions": {
                    "actions": [
                        { "action": "c2pa.created" },
                        { "action": "c2pa.color_adjustments" }
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
                        "explanation": "Claim signature passed verification."
                    }
                ]
            }
        }
    ],
    "validation_results": {
        "spec_version": "2.2",
        "media_type": "video/mp4"
    }
}
"""

def test_parse_crjson_model():
    report = parse_crjson(
        raw_json=SAMPLE_CRJSON,
        media_type="video/mp4",
        elapsed_seconds=0.004,
        core_seconds=0.003
    )

    assert report.has_credentials is True
    assert report.badge == BadgeState.SIGNED
    assert report.spec_version == "2.2"
    assert report.core_seconds == 0.003
    assert report.active_manifest is not None

    manifest = report.active_manifest
    assert manifest.label == "urn:c2pa:test_manifest"
    assert manifest.title == "Authenticated Video Sample"
    assert manifest.claim_generator == "CredentioCamera 1.4.2"

    assert manifest.signature is not None
    assert manifest.signature.issuer == "Google Trust Services LLC"
    assert manifest.signature.algorithm == "es256"

    assert len(manifest.assertions) == 2
    actions = [a for a in manifest.assertions if a.kind == AssertionKind.ACTIONS]
    assert len(actions) == 1
    assert actions[0].summary == "c2pa.created, c2pa.color_adjustments"

    assert len(manifest.validation_statuses) == 1
    assert manifest.validation_statuses[0].code == "claimSignature.validated"
    assert manifest.validation_statuses[0].severity == Severity.INFO


@pytest.mark.skipif(_find_library_path() is None, reason="Native libcredentio_c shared library not built yet")
def test_native_validator_integration():
    from credentio import Validator
    with Validator(skip_trust_checks=True) as val:
        # Validate dummy bytes should return has_credentials=False without crashing
        report = val.validate_bytes(b"non-c2pa-dummy-file-content", media_type="image/jpeg")
        assert report.has_credentials is False
        assert report.badge == BadgeState.UNSIGNED


def test_assertion_summaries():
    sample_json = """
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
    report = parse_crjson(raw_json=sample_json, media_type="image/jpeg")
    assert report.active_manifest is not None
    active = report.active_manifest

    summaries = {a.label: a.summary for a in active.assertions}
    assert summaries["c2pa.training-mining"] == "AI Training: ai_generative_training=notAllowed, data_mining=notAllowed"
    assert summaries["c2pa.digital_source_type"] == "trainedAlgorithmicMedia"
    assert summaries["c2pa.ai_generative_info"] == "model: Imagen 3.0"


def test_portlandia_probe_mp4():
    raw_payload = """
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
                        {"code": "claimSignature.validated"}
                    ]
                }
            }
        ]
    }
    """
    report = parse_crjson(raw_json=raw_payload, media_type="video/mp4")
    assert report.has_credentials is True
    assert report.badge == BadgeState.SIGNED

    active = report.active_manifest
    assert active is not None
    assert active.claim_generator == "Google C2PA Core Generator Library 969395858"
    assert active.format == "video/mp4"

    summaries = {a.label: a.summary for a in active.assertions}
    assert summaries["c2pa.actions.v2"] == "c2pa.created (trainedAlgorithmicMedia), c2pa.edited (trainedAlgorithmicMedia)"
    assert active.signature is not None
    assert active.signature.issuer == "TESTING Google C2PA Qual Media Services ICA G1"


def test_sniff_media_type():
    from credentio.validator import sniff_media_type
    assert sniff_media_type(b"ID3\x03\x00\x00\x00\x00;jGEOB") == "audio/mpeg"
    assert sniff_media_type(b"fLaC\x00\x00\x00\x22") == "audio/flac"
    assert sniff_media_type(b"RIFF\x24\x08\x00\x00WAVEfmt ") == "audio/wav"
    assert sniff_media_type(b"\xff\xd8\xff\xe0\x00\x10JFIF") == "image/jpeg"
    assert sniff_media_type(b"\x89PNG\r\n\x1a\n\x00\x00") == "image/png"
    assert sniff_media_type(b"%PDF-1.7") == "application/pdf"
    assert sniff_media_type(b"\x00\x00\x00\x1cftypavif\x00\x00\x00\x00") == "image/avif"
    assert sniff_media_type(b"\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00") == "video/mp4"


TEST_CLAIM_SIGNER_KEY_PEM = """-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgP1t9Nc4kMdAQMHs5
DjHjrBFHRIOC24W+tvrPF3gS1JWhRANCAAQ+mATlGlQUDF4bGnJvbd5ehII2+Hnu
r+O6rqzDEiG+yWvazpNchCzDXds0DQAe7nsq1Jbd6qbZaab4eJMYakbO
-----END PRIVATE KEY-----
"""

TEST_CLAIM_SIGNER_CERT_PEM = """-----BEGIN CERTIFICATE-----
MIIB7jCCAZSgAwIBAgIQNX8XBvVYTVppX0cFOnohFzAKBggqhkjOPQQDAjA6MRcw
FQYDVQQKEw5DcmVkZW50aW8gVGVzdDEfMB0GA1UEAxMWQ3JlZGVudGlvIFRlc3Qg
Um9vdCBDQTAeFw0yNjEwMTcxODI0NTRaFw0yNzEwMTcxODI0NTRaMD8xFzAVBgNV
BAoTDkNyZWRlbnRpbyBUZXN0MSQwIgYDVQQDExtDcmVkZW50aW8gVGVzdCBDbGFp
bSBTaWduZXIwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNCAAQ+mATlGlQUDF4bGnJv
bd5ehII2+Hnur+O6rqzDEiG+yWvazpNchCzDXds0DQAe7nsq1Jbd6qbZaab4eJMY
akbOo3cwdTAOBgNVHQ8BAf8EBAMCB4AwFQYDVR0lBA4wDAYKKwYBBAGD6F4CATAM
BgNVHRMBAf8EAjAAMB0GA1UdDgQWBBQFXmMIouQm0lMTvkeJO2iPSyhm2jAfBgNV
HSMEGDAWgBSXI/fOmvyeRDvJE0mnuXPhzwfY6jAKBggqhkjOPQQDAgNIADBFAiEA
1QoxfwjNbRyWPhypgSxLFkwhUAeqSDNPybpo8+hnVMECIA+pv4x+d0Yey3G2xbg5
qUlmi2S1eV8f19ACqbGCN0er
-----END CERTIFICATE-----
"""

TEST_ROOT_CA_CERT_PEM = """-----BEGIN CERTIFICATE-----
MIIBtTCCAVugAwIBAgIRAIB04rVlhoVgFjG20uDN2oMwCgYIKoZIzj0EAwIwOjEX
MBUGA1UEChMOQ3JlZGVudGlvIFRlc3QxHzAdBgNVBAMTFkNyZWRlbnRpbyBUZXN0
IFJvb3QgQ0EwHhcNMjYxMDE3MTgyNDU0WhcNMzYxMDE0MTgyNDU0WjA6MRcwFQYD
VQQKEw5DcmVkZW50aW8gVGVzdDEfMB0GA1UEAxMWQ3JlZGVudGlvIFRlc3QgUm9v
dCBDQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABOwYL78IKaNH3kHfkUbiJ14I
CE+Oqt2d5Ff+cRdEWdjIC4anDZV59g1l1xPbR64Vekz92haftrPF5ASYbiFFPKOj
QjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBSX
I/fOmvyeRDvJE0mnuXPhzwfY6jAKBggqhkjOPQQDAgNIADBFAiAs080K/Oc04cxa
OztvtOkuwBWBhpirSO33aypvsMndPgIhAKglQdIKHp8leqLhEW5CYYZzETU0mZLc
OQuIj7JcTfYt
-----END CERTIFICATE-----
"""

# Minimal valid 1x1 RGB PNG image
MINIMAL_PNG_BYTES = (
    b"\x89PNG\r\n\x1a\n"
    b"\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde"
    b"\x00\x00\x00\x0cIDATx\x9cc\xf8\xcf\xc0\x00\x00\x03\x01\x01\x00\x18\xdd\x8d\xb0"
    b"\x00\x00\x00\x00IEND\xaeB`\x82"
)


@pytest.mark.skipif(_find_library_path() is None, reason="Native libcredentio_c shared library not built yet")
def test_sign_and_validate_round_trip(tmp_path):
    from credentio import Signer, Validator

    with Signer(
        claim_signer_key_pem=TEST_CLAIM_SIGNER_KEY_PEM,
        claim_signer_cert_pem=TEST_CLAIM_SIGNER_CERT_PEM,
        generator_name="PythonCredentioSigner",
        generator_version="0.2.0",
    ) as signer:
        res = signer.sign_bytes(
            MINIMAL_PNG_BYTES,
            media_type="image/png",
            digital_source_type="http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture",
            custom_assertions={
                "c2pa.training-mining": {
                    "entries": {
                        "c2pa.ai_generative_training": {"use": "notAllowed"}
                    }
                }
            },
        )
        assert res.signed_bytes is not None
        assert res.byte_size > len(MINIMAL_PNG_BYTES)

        # Also test file-to-file signing
        in_file = tmp_path / "source.png"
        out_file = tmp_path / "signed.png"
        in_file.write_bytes(MINIMAL_PNG_BYTES)
        file_res = signer.sign_file(in_file, out_file)
        assert file_res.byte_size > len(MINIMAL_PNG_BYTES)

    with Validator(
        claim_signer_trust_pem=TEST_ROOT_CA_CERT_PEM,
        skip_trust_checks=True,
    ) as validator:
        report = validator.validate_bytes(res.signed_bytes, media_type="image/png")
        assert report.has_credentials is True
        assert report.badge == BadgeState.SIGNED
        assert report.active_manifest is not None
        assert "PythonCredentioSigner" in (report.active_manifest.claim_generator or "")

        file_report = validator.validate_file(out_file)
        assert file_report.has_credentials is True
        assert file_report.badge == BadgeState.SIGNED




