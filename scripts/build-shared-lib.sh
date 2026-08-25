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
# build-shared-lib.sh: builds libcredentio_c shared library (.dylib or .so)
# via Bazel and bundles it for the Python (cffi) and Go (cgo) packages.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PIN_FILE="${REPO_DIR}/.credentio-pin"
DEFAULT_SHA="4ac69fc58256d3871e765f615254373e19e250e9"
if [[ -f "${PIN_FILE}" ]]; then
  DEFAULT_SHA="$(tr -d '[:space:]' < "${PIN_FILE}")"
fi

CREDENTIO_GIT_URL="${CREDENTIO_GIT_URL:-https://mediaprovenance.googlesource.com/credentio}"
CREDENTIO_SHA="${CREDENTIO_SHA:-${DEFAULT_SHA}}"

echo "=== Building libcredentio_c shared library ==="

# 1. Locate or clone Credentio checkout
CREDENTIO_DIR="${CREDENTIO_DIR:-}"
if [[ -z "${CREDENTIO_DIR}" ]]; then
  for candidate in \
    "${HOME}/projects/credentio" \
    "${REPO_DIR}/../credentio" \
    "/workspace/credentio"; do
    if [[ -d "${candidate}" && -f "${candidate}/MODULE.bazel" ]]; then
      CREDENTIO_DIR="${candidate}"
      break
    fi
  done
fi

if [[ -z "${CREDENTIO_DIR}" || ! -d "${CREDENTIO_DIR}" ]]; then
  echo "==> Credentio checkout not found locally. Cloning from ${CREDENTIO_GIT_URL}..."
  CLONE_DIR="$(mktemp -d /tmp/credentio-clone.XXXXXX)"
  git clone "${CREDENTIO_GIT_URL}" "${CLONE_DIR}"
  (cd "${CLONE_DIR}" && git checkout "${CREDENTIO_SHA}")
  CREDENTIO_DIR="${CLONE_DIR}"
fi

echo "==> Using Credentio at: ${CREDENTIO_DIR}"

# 2. Overlay native files into Credentio bindings_c/
OVERLAY_DIR="${CREDENTIO_DIR}/bindings_c"
mkdir -p "${OVERLAY_DIR}"
cp -f "${REPO_DIR}/native/credentio_c.h" "${OVERLAY_DIR}/credentio_c.h"
cp -f "${REPO_DIR}/native/credentio_c.cc" "${OVERLAY_DIR}/credentio_c.cc"
cp -f "${REPO_DIR}/native/BUILD" "${OVERLAY_DIR}/BUILD"
echo "==> Overlaid C-ABI wrapper to ${OVERLAY_DIR}"

# 3. Build shared library via Bazel
echo "==> Invoking Bazel build //bindings_c:libcredentio_c (startup flags: ${CREDENTIO_BAZEL_STARTUP_FLAGS:-none}, extra flags: ${CREDENTIO_EXTRA_BAZEL_FLAGS:-none})..."
# shellcheck disable=SC2086
(
  cd "${CREDENTIO_DIR}"
  bazel ${CREDENTIO_BAZEL_STARTUP_FLAGS:-} build ${CREDENTIO_EXTRA_BAZEL_FLAGS:-} //bindings_c:libcredentio_c
)

BAZEL_BIN="$(cd "${CREDENTIO_DIR}" && bazel info bazel-bin 2>/dev/null)"
LIB_SOURCE=""

for candidate in \
  "${BAZEL_BIN}/bindings_c/libcredentio_c.dylib" \
  "${BAZEL_BIN}/bindings_c/liblibcredentio_c.dylib" \
  "${BAZEL_BIN}/bindings_c/libcredentio_c.so" \
  "${BAZEL_BIN}/bindings_c/liblibcredentio_c.so"; do
  if [[ -f "${candidate}" ]]; then
    LIB_SOURCE="${candidate}"
    break
  fi
done

if [[ -z "${LIB_SOURCE}" || ! -f "${LIB_SOURCE}" ]]; then
  echo "ERROR: Could not locate built shared library in ${BAZEL_BIN}/bindings_c/" >&2
  exit 1
fi

EXT="${LIB_SOURCE##*.}"
TARGET_LIB_NAME="libcredentio_c.${EXT}"

echo "==> Built shared library: ${LIB_SOURCE}"

# 4. Copy to python/ and go/ packaging targets with write permissions
PY_LIB_DIR="${REPO_DIR}/python/src/credentio/lib"
PY_INC_DIR="${REPO_DIR}/python/src/credentio/include"
GO_LIB_DIR="${REPO_DIR}/go/lib"
GO_INC_DIR="${REPO_DIR}/go/include"

mkdir -p "${PY_LIB_DIR}" "${PY_INC_DIR}" "${GO_LIB_DIR}" "${GO_INC_DIR}"

# Remove existing files to prevent read-only overwrite permission errors
rm -f "${PY_LIB_DIR}/${TARGET_LIB_NAME}"
rm -f "${GO_LIB_DIR}/${TARGET_LIB_NAME}"
rm -f "${REPO_DIR}/native/${TARGET_LIB_NAME}"

cp -f "${LIB_SOURCE}" "${PY_LIB_DIR}/${TARGET_LIB_NAME}"
cp -f "${LIB_SOURCE}" "${GO_LIB_DIR}/${TARGET_LIB_NAME}"
chmod 755 "${PY_LIB_DIR}/${TARGET_LIB_NAME}" "${GO_LIB_DIR}/${TARGET_LIB_NAME}"

cp -f "${REPO_DIR}/native/credentio_c.h" "${PY_INC_DIR}/credentio_c.h"
cp -f "${REPO_DIR}/native/credentio_c.h" "${GO_INC_DIR}/credentio_c.h"

# Copy upstream license for distribution compliance
if [[ -f "${CREDENTIO_DIR}/LICENSE" ]]; then
  cp -f "${CREDENTIO_DIR}/LICENSE" "${REPO_DIR}/python/LICENSE.credentio"
  cp -f "${CREDENTIO_DIR}/LICENSE" "${REPO_DIR}/go/LICENSE.credentio"
fi

# Fix macOS dynamic library install name if on darwin
if [[ "$(uname)" == "Darwin" ]] && command -v install_name_tool >/dev/null 2>&1; then
  install_name_tool -id "@rpath/${TARGET_LIB_NAME}" "${PY_LIB_DIR}/${TARGET_LIB_NAME}" 2>/dev/null || true
  install_name_tool -id "@rpath/${TARGET_LIB_NAME}" "${GO_LIB_DIR}/${TARGET_LIB_NAME}" 2>/dev/null || true
fi

echo "======================================================="
echo "SUCCESS: Staged ${TARGET_LIB_NAME} into:"
echo "  - python/src/credentio/lib/${TARGET_LIB_NAME}"
echo "  - go/lib/${TARGET_LIB_NAME}"
echo "======================================================="
