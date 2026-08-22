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

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Optional

from . import __version__
from .models import BadgeState, ProvenanceReport
from .validator import CredentioError, Validator

def format_human_output(report: ProvenanceReport, file_path: Path) -> str:
    size_mb = os.path.getsize(file_path) / (1024.0 * 1024.0)
    lines = [
        "=" * 64,
        "  Google Credentio C2PA Validation Report",
        "=" * 64,
        f"Asset:       {file_path.name} ({size_mb:.2f} MB, {report.media_type or 'unknown'})",
        f"Path:        {file_path.resolve()}",
        f"Status:      {report.badge.value.upper()}",
    ]

    if report.has_credentials and report.active_manifest:
        m = report.active_manifest
        lines.extend([
            f"Generator:   {m.claim_generator or '—'}",
            f"Issuer:      {m.signature.issuer if m.signature else '—'}",
            f"Format/Spec: {m.format or '—'} (C2PA {report.spec_version or '—'})",
            f"Assertions:  {len(m.assertions)} attached",
            f"Statuses:    {len(m.validation_statuses)} reported",
        ])

    if report.core_seconds is not None:
        lines.append(f"Core Time:   {report.core_seconds * 1000.0:.2f} ms")
    lines.append(f"Wall Time:   {report.elapsed_seconds * 1000.0:.2f} ms")
    lines.append("=" * 64)
    return "\n".join(lines)


def format_json_output(report: ProvenanceReport, file_path: Path) -> str:
    m = report.active_manifest
    data = {
        "asset_path": str(file_path.resolve()),
        "byte_size": os.path.getsize(file_path),
        "media_type": report.media_type,
        "engine_id": report.engine_id,
        "has_credentials": report.has_credentials,
        "badge": report.badge.value,
        "spec_version": report.spec_version,
        "elapsed_seconds": report.elapsed_seconds,
        "core_seconds": report.core_seconds,
        "active_manifest": {
            "label": m.label,
            "title": m.title,
            "claim_generator": m.claim_generator,
            "format": m.format,
            "is_update_manifest": m.is_update_manifest,
            "signature": {
                "issuer": m.signature.issuer,
                "algorithm": m.signature.algorithm,
                "time": m.signature.time.isoformat() if m.signature and m.signature.time else None,
                "cert_serial_number": m.signature.cert_chain_summary if m.signature else None,
            } if m.signature else None,
            "assertions_count": len(m.assertions),
            "validation_statuses_count": len(m.validation_statuses),
        } if m else None,
    }
    return json.dumps(data, indent=2)


def main(args: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="credentio",
        description="Google Credentio C2PA Content Credentials Command-Line Validator"
    )
    parser.add_argument("--version", "-v", action="version", version=f"%(prog)s {__version__}")

    subparsers = parser.add_subparsers(dest="subcommand", help="Available subcommands")

    # validate subcommand
    val_parser = subparsers.add_parser("validate", help="Validate C2PA content credentials in a media file")
    val_parser.add_argument("path", type=Path, help="Path to media asset (image, video, audio, document)")
    val_parser.add_argument("--media-type", "-m", type=str, default=None, help="Optional IANA media type (e.g. image/jpeg)")
    val_parser.add_argument("--json", action="store_true", help="Output structured JSON")
    val_parser.add_argument("--claim-signer-trust", type=Path, default=None, help="Path to claim signer trust anchors PEM")
    val_parser.add_argument("--tsa-trust", type=Path, default=None, help="Path to TSA trust anchors PEM")
    val_parser.add_argument("--skip-trust-checks", action="store_true", default=True, help="Skip trust anchor checks (default: True)")

    parsed = parser.parse_args(args)

    if not parsed.subcommand:
        parser.print_help()
        return 0

    if parsed.subcommand == "validate":
        if not parsed.path.is_file():
            print(f"Error: file not found at {parsed.path}", file=sys.stderr)
            return 3

        claim_pem = parsed.claim_signer_trust.read_text("utf-8") if parsed.claim_signer_trust else None
        tsa_pem = parsed.tsa_trust.read_text("utf-8") if parsed.tsa_trust else None
        skip_trust = False if (claim_pem or tsa_pem) else parsed.skip_trust_checks

        try:
            with Validator(claim_signer_trust_pem=claim_pem, tsa_trust_pem=tsa_pem, skip_trust_checks=skip_trust) as v:
                report = v.validate_file(parsed.path, media_type=parsed.media_type)
        except CredentioError as e:
            print(f"Error: {e}", file=sys.stderr)
            return 3
        except Exception as e:
            print(f"Unexpected error: {e}", file=sys.stderr)
            return 3

        if parsed.json:
            print(format_json_output(report, parsed.path))
        else:
            print(format_human_output(report, parsed.path))

        if report.badge == BadgeState.SIGNED:
            return 0
        elif report.badge == BadgeState.UNSIGNED:
            return 1
        elif report.badge == BadgeState.INVALID:
            return 2
        return 0

    return 0


if __name__ == "__main__":
    sys.exit(main())
