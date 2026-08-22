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
# build-swift-xcframework.sh — builds the Credentio C-ABI static library
# and packages it into swift/CredentioC.xcframework for native Swift consumption.
#
# Must be executed on macOS host with Xcode and Bazel installed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_XCFRAMEWORK="${REPO_DIR}/swift/CredentioC.xcframework"

echo "=== Building Credentio C-ABI static xcframework for Swift ==="

# 1. Locate Credentio checkout
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
  echo "ERROR: Credentio checkout not found. Set CREDENTIO_DIR=/path/to/credentio" >&2
  exit 1
fi

echo "==> Using Credentio at: ${CREDENTIO_DIR}"

# 2. Overlay C-ABI wrapper into Credentio tree (under bindings_c/)
OVERLAY_TARGET="${CREDENTIO_DIR}/bindings_c"
mkdir -p "${OVERLAY_TARGET}"
cp -f "${REPO_DIR}/native/credentio_c.h" "${OVERLAY_TARGET}/credentio_c.h"
cp -f "${REPO_DIR}/native/credentio_c.cc" "${OVERLAY_TARGET}/credentio_c.cc"
cp -f "${REPO_DIR}/native/BUILD" "${OVERLAY_TARGET}/BUILD"
echo "==> Overlaid C-ABI wrapper to ${OVERLAY_TARGET}"

# 3. Build static library with Bazel for macOS arm64
echo "==> Invoking Bazel build //bindings_c:credentio_c..."
(
  cd "${CREDENTIO_DIR}"
  bazel build //bindings_c:credentio_c
)

# 4. Prepare temporary staging for static archive merge
STAGE_DIR="$(mktemp -d /tmp/credentio-c-stage.XXXXXX)"
trap 'rm -rf "${STAGE_DIR}"' EXIT

HEADERS_DIR="${STAGE_DIR}/include"
mkdir -p "${HEADERS_DIR}"
cp -f "${REPO_DIR}/native/credentio_c.h" "${HEADERS_DIR}/credentio_c.h"
cp -f "${REPO_DIR}/native/module.modulemap" "${HEADERS_DIR}/module.modulemap"

echo "==> Resolving static archive dependency closure via Bazel CcInfo..."
EXEC_ROOT="$(cd "${CREDENTIO_DIR}" && bazel info execution_root 2>/dev/null || echo "")"
BAZEL_BIN="$(cd "${CREDENTIO_DIR}" && bazel info bazel-bin 2>/dev/null || echo "")"

RAW_LIST="${STAGE_DIR}/raw_archives.txt"
ARCHIVE_LIST="${STAGE_DIR}/archives.txt"
touch "${RAW_LIST}"

# Query transitive static libraries from CcInfo linking context
STAGED_EXPR='"\n".join([f.path for li in providers(target)["CcInfo"].linking_context.linker_inputs.to_list() for lib in li.libraries for f in [lib.static_library, lib.pic_static_library] if f])'

CQUERY_OUT="$(cd "${CREDENTIO_DIR}" && bazel cquery //bindings_c:credentio_c --output=starlark --starlark:expr="${STAGED_EXPR}" 2>/dev/null || true)"

if [[ -n "${CQUERY_OUT}" ]]; then
  while IFS= read -r rel_path; do
    [[ -z "${rel_path}" ]] && continue
    if [[ "${rel_path}" == /* && -f "${rel_path}" ]]; then
      echo "${rel_path}" >> "${RAW_LIST}"
    elif [[ -n "${EXEC_ROOT}" && -f "${EXEC_ROOT}/${rel_path}" ]]; then
      echo "${EXEC_ROOT}/${rel_path}" >> "${RAW_LIST}"
    elif [[ -f "${CREDENTIO_DIR}/${rel_path}" ]]; then
      echo "${CREDENTIO_DIR}/${rel_path}" >> "${RAW_LIST}"
    elif [[ -n "${BAZEL_BIN}" && -f "${BAZEL_BIN}/${rel_path}" ]]; then
      echo "${BAZEL_BIN}/${rel_path}" >> "${RAW_LIST}"
    fi
  done <<< "${CQUERY_OUT}"
fi

# Also scan bazel-bin for any complementary static archives (.a or .lo)
if [[ -n "${BAZEL_BIN}" && -d "${BAZEL_BIN}" ]]; then
  find "${BAZEL_BIN}" \( -name "*.a" -o -name "*.lo" \) -type f >> "${RAW_LIST}" 2>/dev/null || true
fi

# Deduplicate and verify archive files
if [[ -f "${RAW_LIST}" ]]; then
  sort -u "${RAW_LIST}" | while IFS= read -r f; do
    [[ -n "$f" && -r "$f" ]] && echo "$f"
  done > "${ARCHIVE_LIST}"
fi

ARCHIVE_COUNT="$(wc -l < "${ARCHIVE_LIST}" | tr -d ' ')"
echo "==> Found ${ARCHIVE_COUNT} static archive(s) to merge."

if [[ "${ARCHIVE_COUNT}" -eq 0 ]]; then
  echo "ERROR: Could not resolve static archives for //bindings_c:credentio_c." >&2
  exit 1
fi

MERGED_LIB="${STAGE_DIR}/libCredentioC.a"
echo "==> Merging static archives with libtool..."
libtool -static -o "${MERGED_LIB}" -filelist "${ARCHIVE_LIST}"

# 5. Package into XCFramework with xcodebuild
echo "==> Packaging into XCFramework at ${OUTPUT_XCFRAMEWORK}..."
rm -rf "${OUTPUT_XCFRAMEWORK}"
xcodebuild -create-xcframework \
  -library "${MERGED_LIB}" \
  -headers "${HEADERS_DIR}" \
  -output "${OUTPUT_XCFRAMEWORK}"

echo "======================================================="
echo "SUCCESS: Created ${OUTPUT_XCFRAMEWORK}"
echo "======================================================="
