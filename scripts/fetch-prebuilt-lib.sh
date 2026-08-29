#!/usr/bin/env bash
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
#
# fetch-prebuilt-lib.sh: downloads pre-compiled native libcredentio_c shared library
# from GitHub Releases for Go (cgo) and Python developers who do not have Bazel installed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION="${1:-0.1.4}"
VERSION="${VERSION#v}" # strip leading v if provided

REPO="ghchinoy/credentio-contributions"
BASE_URL="https://github.com/${REPO}/releases/download/v${VERSION}"

# Detect OS and Arch
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "${ARCH}" in
  x86_64|amd64)
    ARCH_NAME="amd64"
    ;;
  arm64|aarch64)
    ARCH_NAME="arm64"
    ;;
  *)
    echo "ERROR: Unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

case "${OS}" in
  darwin)
    EXT="dylib"
    PLATFORM="darwin-${ARCH_NAME}"
    ;;
  linux)
    EXT="so"
    PLATFORM="linux-${ARCH_NAME}"
    ;;
  *)
    echo "ERROR: Unsupported OS: ${OS}" >&2
    exit 1
    ;;
esac

TARGET_LIB="libcredentio_c.${EXT}"
DOWNLOAD_URL="${BASE_URL}/libcredentio_c-${PLATFORM}.${EXT}"

echo "=== Fetching prebuilt ${TARGET_LIB} for ${PLATFORM} (v${VERSION}) ==="
echo "Downloading from: ${DOWNLOAD_URL}"

TMP_FILE="$(mktemp /tmp/credentio-lib.XXXXXX)"
trap 'rm -f "${TMP_FILE}"' EXIT

if curl -fL --progress-bar -o "${TMP_FILE}" "${DOWNLOAD_URL}"; then
  echo "==> Download completed successfully."
else
  # Fallback to direct name if platform-specific asset name not found
  FALLBACK_URL="${BASE_URL}/${TARGET_LIB}"
  echo "==> Trying release asset fallback: ${FALLBACK_URL}"
  if ! curl -fL --progress-bar -o "${TMP_FILE}" "${FALLBACK_URL}"; then
    echo "ERROR: Failed to download prebuilt binary from release v${VERSION}." >&2
    echo "Make sure release v${VERSION} exists at https://github.com/${REPO}/releases" >&2
    exit 1
  fi
fi

# Stage into go/ and python/ directories
mkdir -p "${REPO_DIR}/go/lib" "${REPO_DIR}/go/include"
mkdir -p "${REPO_DIR}/python/src/credentio/lib" "${REPO_DIR}/python/src/credentio/include"

cp -f "${TMP_FILE}" "${REPO_DIR}/go/lib/${TARGET_LIB}"
cp -f "${TMP_FILE}" "${REPO_DIR}/python/src/credentio/lib/${TARGET_LIB}"
chmod 755 "${REPO_DIR}/go/lib/${TARGET_LIB}" "${REPO_DIR}/python/src/credentio/lib/${TARGET_LIB}"

if [[ -f "${REPO_DIR}/native/credentio_c.h" ]]; then
  cp -f "${REPO_DIR}/native/credentio_c.h" "${REPO_DIR}/go/include/credentio_c.h"
  cp -f "${REPO_DIR}/native/credentio_c.h" "${REPO_DIR}/python/src/credentio/include/credentio_c.h"
fi

echo "======================================================="
echo "SUCCESS: Installed prebuilt ${TARGET_LIB} into:"
echo "  - go/lib/${TARGET_LIB}"
echo "  - python/src/credentio/lib/${TARGET_LIB}"
echo "You can now build with CGO or run Python native tests!"
echo "======================================================="
