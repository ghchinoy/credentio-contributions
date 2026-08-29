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

import mimetypes
import os
import time
from pathlib import Path
from typing import Optional, Union

from ._ffi import ffi, get_lib
from .models import ProvenanceReport, parse_crjson

def sniff_media_type(header: bytes) -> Optional[str]:
    """Sniffs the true MIME type by inspecting leading magic bytes."""
    if len(header) >= 3 and header[:3] == b"ID3":
        return "audio/mpeg"
    if len(header) >= 4 and header[:4] == b"fLaC":
        return "audio/flac"
    if len(header) >= 3 and header[:3] == b"\xff\xd8\xff":
        return "image/jpeg"
    if len(header) >= 8 and header[:8] == b"\x89PNG\r\n\x1a\n":
        return "image/png"
    if len(header) >= 6 and (header[:6] == b"GIF87a" or header[:6] == b"GIF89a"):
        return "image/gif"
    if len(header) >= 4 and header[:4] == b"%PDF":
        return "application/pdf"
    if len(header) >= 12 and header[:4] == b"RIFF":
        form = header[8:12]
        if form == b"WAVE":
            return "audio/wav"
        if form == b"WEBP":
            return "image/webp"
        if form == b"AVI ":
            return "video/x-msvideo"
    if len(header) >= 12 and header[4:8] == b"ftyp":
        brand = header[8:12]
        if brand in (b"avif", b"avis"):
            return "image/avif"
        if brand in (b"heic", b"heix", b"mif1"):
            return "image/heic"
        if brand == b"M4A ":
            return "audio/mp4"
        return "video/mp4"
    return None


class CredentioError(RuntimeError):
    """Raised when Credentio encounters an unrecoverable validation error."""
    pass


class Validator:
    """Validator instance wrapping the native Google Credentio C-ABI."""

    def __init__(
        self,
        claim_signer_trust_pem: Optional[str] = None,
        tsa_trust_pem: Optional[str] = None,
        skip_trust_checks: bool = True
    ):
        self._lib = get_lib()
        self._ptr = None

        claim_c = ffi.new("char[]", claim_signer_trust_pem.encode("utf-8")) if claim_signer_trust_pem else ffi.NULL
        tsa_c = ffi.new("char[]", tsa_trust_pem.encode("utf-8")) if tsa_trust_pem else ffi.NULL
        skip_c = 1 if skip_trust_checks else 0

        self._ptr = self._lib.cr_validator_create(claim_c, tsa_c, skip_c)
        if not self._ptr:
            raise CredentioError("Failed to initialize native Credentio validator instance.")

    def __enter__(self) -> "Validator":
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    def close(self):
        """Releases the underlying C-ABI validator resources."""
        if self._ptr:
            self._lib.cr_validator_free(self._ptr)
            self._ptr = None

    def __del__(self):
        self.close()

    def validate_file(
        self,
        file_path: Union[str, Path],
        media_type: Optional[str] = None
    ) -> ProvenanceReport:
        """Validates a local media asset file and returns a ProvenanceReport.

        Args:
            file_path: Path to the media asset (image, video, audio, document).
            media_type: Optional IANA MIME type (e.g. 'image/jpeg'). If None, inferred.
        """
        if not self._ptr:
            raise CredentioError("Validator has already been closed.")

        path_str = str(Path(file_path).resolve())
        if not os.path.isfile(path_str):
            raise FileNotFoundError(f"File not found: {path_str}")

        if not media_type:
            try:
                with open(path_str, "rb") as f:
                    header = f.read(32)
                media_type = sniff_media_type(header)
            except Exception:
                media_type = None
            if not media_type:
                media_type, _ = mimetypes.guess_type(path_str)

        path_c = ffi.new("char[]", path_str.encode("utf-8"))
        media_type_c = ffi.new("char[]", media_type.encode("utf-8")) if media_type else ffi.NULL
        status_ptr = ffi.new("int*")

        start_time = time.perf_counter()
        json_ptr = self._lib.cr_validate_file(self._ptr, path_c, media_type_c, status_ptr)
        elapsed_seconds = time.perf_counter() - start_time
        core_seconds = self._lib.cr_last_internal_seconds(self._ptr)

        status = status_ptr[0]

        if not json_ptr or status == 1:  # CR_STATUS_NO_CREDENTIALS
            if json_ptr:
                self._lib.cr_string_free(json_ptr)
            return ProvenanceReport(
                engine_id="credentio",
                engine_name="Credentio (Google)",
                has_credentials=False,
                elapsed_seconds=elapsed_seconds,
                core_seconds=core_seconds,
                media_type=media_type
            )

        if status != 0:
            err_msg = ffi.string(self._lib.cr_last_error(self._ptr)).decode("utf-8", errors="replace")
            if json_ptr:
                self._lib.cr_string_free(json_ptr)
            raise CredentioError(f"Validation failed (code {status}): {err_msg}")

        try:
            raw_json_str = ffi.string(json_ptr).decode("utf-8")
        finally:
            self._lib.cr_string_free(json_ptr)

        return parse_crjson(
            raw_json=raw_json_str,
            media_type=media_type,
            elapsed_seconds=elapsed_seconds,
            core_seconds=core_seconds
        )

    def validate_bytes(
        self,
        data: bytes,
        media_type: Optional[str] = None
    ) -> ProvenanceReport:
        """Validates media asset bytes in memory and returns a ProvenanceReport."""
        if not self._ptr:
            raise CredentioError("Validator has already been closed.")

        if not data:
            raise ValueError("Input bytes cannot be empty.")

        if not media_type and len(data) >= 4:
            media_type = sniff_media_type(data[:32])

        media_type_c = ffi.new("char[]", media_type.encode("utf-8")) if media_type else ffi.NULL
        status_ptr = ffi.new("int*")

        start_time = time.perf_counter()
        json_ptr = self._lib.cr_validate_bytes(self._ptr, data, len(data), media_type_c, status_ptr)
        elapsed_seconds = time.perf_counter() - start_time
        core_seconds = self._lib.cr_last_internal_seconds(self._ptr)

        status = status_ptr[0]

        if not json_ptr or status == 1:
            if json_ptr:
                self._lib.cr_string_free(json_ptr)
            return ProvenanceReport(
                engine_id="credentio",
                engine_name="Credentio (Google)",
                has_credentials=False,
                elapsed_seconds=elapsed_seconds,
                core_seconds=core_seconds,
                media_type=media_type
            )

        if status != 0:
            err_msg = ffi.string(self._lib.cr_last_error(self._ptr)).decode("utf-8", errors="replace")
            if json_ptr:
                self._lib.cr_string_free(json_ptr)
            raise CredentioError(f"Validation failed (code {status}): {err_msg}")

        try:
            raw_json_str = ffi.string(json_ptr).decode("utf-8")
        finally:
            self._lib.cr_string_free(json_ptr)

        return parse_crjson(
            raw_json=raw_json_str,
            media_type=media_type,
            elapsed_seconds=elapsed_seconds,
            core_seconds=core_seconds
        )
