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
from pathlib import Path
import pytest
from credentio.cli import format_human_output, format_json_output, main
from credentio.models import BadgeState, Manifest, ProvenanceReport, SignatureInfo

def test_cli_help(capsys):
    with pytest.raises(SystemExit) as exc:
        main(["validate", "--help"])
    assert exc.value.code == 0
    captured = capsys.readouterr()
    assert "Validate C2PA content credentials" in captured.out or "path" in captured.out


def test_cli_file_not_found(capsys):
    ret = main(["validate", "non_existent_file_path_xyz.jpg"])
    assert ret == 3
    captured = capsys.readouterr()
    assert "not found" in captured.err


def test_cli_format_output(tmp_path):
    dummy_file = tmp_path / "test.jpg"
    dummy_file.write_bytes(b"dummy")

    report = ProvenanceReport(
        engine_id="credentio",
        engine_name="Credentio (Google)",
        has_credentials=True,
        elapsed_seconds=0.005,
        core_seconds=0.003,
        media_type="image/jpeg",
        spec_version="2.2",
        active_manifest=Manifest(
            label="urn:c2pa:test",
            claim_generator="TestAgent 1.0",
            signature=SignatureInfo(issuer="Google Trust Services")
        )
    )

    human = format_human_output(report, dummy_file)
    assert "Google Credentio C2PA Validation Report" in human
    assert "SIGNED" in human
    assert "TestAgent 1.0" in human

    json_str = format_json_output(report, dummy_file)
    parsed = json.loads(json_str)
    assert parsed["badge"] == "signed"
    assert parsed["has_credentials"] is True
    assert parsed["active_manifest"]["claim_generator"] == "TestAgent 1.0"
