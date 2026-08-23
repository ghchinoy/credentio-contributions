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

