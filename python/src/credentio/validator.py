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
