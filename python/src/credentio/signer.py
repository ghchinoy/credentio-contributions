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
import mimetypes
import os
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Optional, Union

from ._ffi import ffi, get_lib
from .validator import CredentioError, sniff_media_type

DIGITAL_SOURCE_TYPE_DIGITAL_capture = "http://cv.iptc.org/newscodes/digitalsourcetype/digitalCapture"
DIGITAL_SOURCE_TYPE_TRAINED_ALGORITHMIC_MEDIA = "http://cv.iptc.org/newscodes/digitalsourcetype/trainedAlgorithmicMedia"
DIGITAL_SOURCE_TYPE_COMPOSITE_WITH_TRAINED_AI = "http://cv.iptc.org/newscodes/digitalsourcetype/compositeWithTrainedAlgorithmicMedia"


@dataclass
class SignResult:
    """Result of an in-process C2PA signing operation."""
    byte_size: int
    elapsed_seconds: float
    core_seconds: float
    media_type: Optional[str] = None
    output_path: Optional[str] = None
    signed_bytes: Optional[bytes] = None


class Signer:
    """Signer instance wrapping the native Google Credentio C-ABI manifest generator."""

    def __init__(
        self,
        claim_signer_key_pem: str,
        claim_signer_cert_pem: str,
        tsa_key_pem: Optional[str] = None,
        tsa_cert_pem: Optional[str] = None,
        generator_name: str = "Credentio",
        generator_version: str = "0.2.2",
    ):
        if not claim_signer_key_pem or not claim_signer_cert_pem:
            raise ValueError("claim_signer_key_pem and claim_signer_cert_pem are required.")

        self._lib = get_lib()
        self._ptr = None

        key_c = ffi.new("char[]", claim_signer_key_pem.encode("utf-8"))
        cert_c = ffi.new("char[]", claim_signer_cert_pem.encode("utf-8"))
        tsa_key_c = ffi.new("char[]", tsa_key_pem.encode("utf-8")) if tsa_key_pem else ffi.NULL
        tsa_cert_c = ffi.new("char[]", tsa_cert_pem.encode("utf-8")) if tsa_cert_pem else ffi.NULL
        gen_name_c = ffi.new("char[]", generator_name.encode("utf-8")) if generator_name else ffi.NULL
        gen_ver_c = ffi.new("char[]", generator_version.encode("utf-8")) if generator_version else ffi.NULL

        self._ptr = self._lib.cr_signer_create(
            key_c, cert_c, tsa_key_c, tsa_cert_c, gen_name_c, gen_ver_c
        )
        if not self._ptr:
            raise CredentioError(
                "Failed to initialize native Credentio signer instance (verify EC P-256 PKCS#8 key and certificate chain)."
            )

    def __enter__(self) -> "Signer":
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()

    def close(self):
        """Releases the underlying C-ABI signer resources."""
        if self._ptr:
            self._lib.cr_signer_free(self._ptr)
            self._ptr = None

    def __del__(self):
        self.close()

    def sign_file(
        self,
        input_path: Union[str, Path],
        output_path: Union[str, Path],
        media_type: Optional[str] = None,
        digital_source_type: Optional[str] = None,
        custom_assertions: Optional[Union[Dict[str, Any], str]] = None,
    ) -> SignResult:
        """Embeds and signs a C2PA manifest into input_path and writes the signed asset to output_path."""
        if not self._ptr:
            raise CredentioError("Signer has already been closed.")

        in_str = str(Path(input_path).resolve())
        out_str = str(Path(output_path).resolve())
        if not os.path.isfile(in_str):
            raise FileNotFoundError(f"Input file not found: {in_str}")

        if not media_type:
            try:
                with open(in_str, "rb") as f:
                    header = f.read(32)
                media_type = sniff_media_type(header)
            except Exception:
                media_type = None
            if not media_type:
                media_type, _ = mimetypes.guess_type(in_str)

        assertions_json: Optional[str] = None
        if isinstance(custom_assertions, str):
            assertions_json = custom_assertions
        elif custom_assertions is not None:
            assertions_json = json.dumps(custom_assertions)

        in_c = ffi.new("char[]", in_str.encode("utf-8"))
        out_c = ffi.new("char[]", out_str.encode("utf-8"))
        media_c = ffi.new("char[]", media_type.encode("utf-8")) if media_type else ffi.NULL
        dst_c = ffi.new("char[]", digital_source_type.encode("utf-8")) if digital_source_type else ffi.NULL
        assertions_c = ffi.new("char[]", assertions_json.encode("utf-8")) if assertions_json else ffi.NULL

        start_time = time.perf_counter()
        status = self._lib.cr_sign_file(self._ptr, in_c, out_c, media_c, dst_c, assertions_c)
        elapsed_seconds = time.perf_counter() - start_time
        core_seconds = self._lib.cr_signer_last_internal_seconds(self._ptr)

        if status != 0:
            err_msg = ffi.string(self._lib.cr_signer_last_error(self._ptr)).decode("utf-8", errors="replace")
            raise CredentioError(f"Signing failed (code {status}): {err_msg}")

        byte_size = os.path.getsize(out_str) if os.path.isfile(out_str) else 0
        return SignResult(
            byte_size=byte_size,
            elapsed_seconds=elapsed_seconds,
            core_seconds=core_seconds,
            media_type=media_type,
            output_path=out_str,
        )

    def sign_bytes(
        self,
        data: bytes,
        media_type: Optional[str] = None,
        digital_source_type: Optional[str] = None,
        custom_assertions: Optional[Union[Dict[str, Any], str]] = None,
    ) -> SignResult:
        """Embeds and signs a C2PA manifest into an in-memory byte buffer and returns a SignResult with signed_bytes."""
        if not self._ptr:
            raise CredentioError("Signer has already been closed.")
        if not data:
            raise ValueError("Input bytes cannot be empty.")

        if not media_type and len(data) >= 4:
            media_type = sniff_media_type(data[:32])

        assertions_json: Optional[str] = None
        if isinstance(custom_assertions, str):
            assertions_json = custom_assertions
        elif custom_assertions is not None:
            assertions_json = json.dumps(custom_assertions)

        media_c = ffi.new("char[]", media_type.encode("utf-8")) if media_type else ffi.NULL
        dst_c = ffi.new("char[]", digital_source_type.encode("utf-8")) if digital_source_type else ffi.NULL
        assertions_c = ffi.new("char[]", assertions_json.encode("utf-8")) if assertions_json else ffi.NULL
        size_ptr = ffi.new("size_t*")
        status_ptr = ffi.new("int*")

        start_time = time.perf_counter()
        out_ptr = self._lib.cr_sign_bytes(
            self._ptr,
            data,
            len(data),
            media_c,
            dst_c,
            assertions_c,
            size_ptr,
            status_ptr,
        )
        elapsed_seconds = time.perf_counter() - start_time
        core_seconds = self._lib.cr_signer_last_internal_seconds(self._ptr)

        status = status_ptr[0]
        if not out_ptr or status != 0:
            err_msg = ffi.string(self._lib.cr_signer_last_error(self._ptr)).decode("utf-8", errors="replace")
            if out_ptr:
                self._lib.cr_bytes_free(out_ptr)
            raise CredentioError(f"Signing failed (code {status}): {err_msg}")

        try:
            out_len = int(size_ptr[0])
            signed_bytes = bytes(ffi.buffer(out_ptr, out_len))
        finally:
            self._lib.cr_bytes_free(out_ptr)

        return SignResult(
            byte_size=len(signed_bytes),
            elapsed_seconds=elapsed_seconds,
            core_seconds=core_seconds,
            media_type=media_type,
            signed_bytes=signed_bytes,
        )
