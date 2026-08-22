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

import os
import platform
import sys
from pathlib import Path
from typing import Optional, Tuple
import cffi

ffi = cffi.FFI()

C_HEADER = """
#define CR_STATUS_OK 0
#define CR_STATUS_NO_CREDENTIALS 1
#define CR_STATUS_INVALID_ARGUMENT 2
#define CR_STATUS_IO_ERROR 3
#define CR_STATUS_INTERNAL_ERROR 4

typedef struct cr_validator cr_validator;

cr_validator* cr_validator_create(
    const char* claim_signer_trust_pem,
    const char* tsa_trust_pem,
    int skip_trust_checks);

void cr_validator_free(cr_validator* validator);

char* cr_validate_file(
    cr_validator* validator,
    const char* file_path,
    const char* media_type,
    int* out_status);

char* cr_validate_bytes(
    cr_validator* validator,
    const uint8_t* bytes,
    size_t count,
    const char* media_type,
    int* out_status);

const char* cr_last_error(cr_validator* validator);
double cr_last_internal_seconds(cr_validator* validator);
void cr_string_free(char* str);
const char* cr_version(void);
"""

ffi.cdef(C_HEADER)

class CredentioLibraryNotFoundError(RuntimeError):
    """Raised when the native libcredentio_c shared library cannot be located."""
    pass

def _find_library_path() -> Optional[Path]:
    # 1. Environment variable override
    env_path = os.environ.get("CREDENTIO_LIB_PATH")
    if env_path and Path(env_path).is_file():
        return Path(env_path)

    # 2. Package bundled lib directory
    pkg_dir = Path(__file__).resolve().parent
    lib_dir = pkg_dir / "lib"
    
    exts = [".dylib", ".so", ".dll"] if platform.system() != "Windows" else [".dll"]
    if platform.system() == "Darwin":
        exts = [".dylib", ".so"]
    elif platform.system() == "Linux":
        exts = [".so"]

    for ext in exts:
        bundled = lib_dir / f"libcredentio_c{ext}"
        if bundled.is_file():
            return bundled

    # 3. Search common system / local build locations
    candidate_dirs = [
        pkg_dir.parent.parent.parent / "native",
        Path("/opt/homebrew/lib"),
        Path("/usr/local/lib"),
        Path.home() / ".local/lib",
    ]

    for c_dir in candidate_dirs:
        for ext in exts:
            candidate = c_dir / f"libcredentio_c{ext}"
            if candidate.is_file():
                return candidate

    return None

_lib = None

def get_lib():
    global _lib
    if _lib is not None:
        return _lib

    lib_path = _find_library_path()
    if not lib_path:
        raise CredentioLibraryNotFoundError(
            "Native libcredentio_c shared library not found. "
            "Build it with 'make build-lib' or set CREDENTIO_LIB_PATH."
        )

    try:
        _lib = ffi.dlopen(str(lib_path))
        return _lib
    except Exception as exc:
        raise CredentioLibraryNotFoundError(
            f"Failed to load native library at {lib_path}: {exc}"
        ) from exc
