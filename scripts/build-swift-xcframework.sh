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
# build-swift-xcframework.sh: builds the Credentio C-ABI static library
# and packages it into swift/CredentioC.xcframework for native Swift consumption.
#
# Must be executed on macOS host with Xcode and Bazel installed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_XCFRAMEWORK="${REPO_DIR}/swift/CredentioC.xcframework"

CREDENTIO_GIT_URL="${CREDENTIO_GIT_URL:-https://mediaprovenance.googlesource.com/credentio}"
CREDENTIO_SHA="${CREDENTIO_SHA:-4ac69fc58256d3871e765f615254373e19e250e9}"

echo "=== Building Credentio C-ABI static xcframework for Swift ==="

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

# 2. Overlay C-ABI wrapper into Credentio tree (under bindings_c/)
OVERLAY_TARGET="${CREDENTIO_DIR}/bindings_c"
mkdir -p "${OVERLAY_TARGET}"
cp -f "${REPO_DIR}/native/credentio_c.h" "${OVERLAY_TARGET}/credentio_c.h"
cp -f "${REPO_DIR}/native/credentio_c.cc" "${OVERLAY_TARGET}/credentio_c.cc"
cp -f "${REPO_DIR}/native/BUILD" "${OVERLAY_TARGET}/BUILD"
echo "==> Overlaid C-ABI wrapper to ${OVERLAY_TARGET}"

STAGE_DIR="$(mktemp -d /tmp/credentio-c-stage.XXXXXX)"
trap 'rm -rf "${STAGE_DIR}"' EXIT

HEADERS_DIR="${STAGE_DIR}/include"
mkdir -p "${HEADERS_DIR}"
cp -f "${REPO_DIR}/native/credentio_c.h" "${HEADERS_DIR}/credentio_c.h"
cp -f "${REPO_DIR}/native/module.modulemap" "${HEADERS_DIR}/module.modulemap"

# Copy license if available
if [[ -f "${CREDENTIO_DIR}/LICENSE" ]]; then
  cp -f "${CREDENTIO_DIR}/LICENSE" "${HEADERS_DIR}/LICENSE.credentio"
fi

# Function to build and resolve static archive for a target configuration
build_static_archive() {
  local label="$1"
  local extra_flags="${2:-}"
  local out_file="${STAGE_DIR}/libCredentioC_${label}.a"

  echo "==> Building static archive for ${label} with Bazel (flags: ${extra_flags})..."
  # shellcheck disable=SC2086
  (
    cd "${CREDENTIO_DIR}"
    bazel build ${extra_flags} //bindings_c:credentio_c
  )

  local raw_list="${STAGE_DIR}/raw_archives_${label}.txt"
  local archive_list="${STAGE_DIR}/archives_${label}.txt"
  touch "${raw_list}"

  local exec_root
  local bazel_bin
  exec_root="$(cd "${CREDENTIO_DIR}" && bazel info execution_root 2>/dev/null || echo "")"
  bazel_bin="$(cd "${CREDENTIO_DIR}" && bazel info bazel-bin 2>/dev/null || echo "")"

  local staged_expr='"\n".join([f.path for li in providers(target)["CcInfo"].linking_context.linker_inputs.to_list() for lib in li.libraries for f in [lib.static_library, lib.pic_static_library] if f])'
  # shellcheck disable=SC2086
  local cquery_out
  cquery_out="$(cd "${CREDENTIO_DIR}" && bazel cquery ${extra_flags} //bindings_c:credentio_c --output=starlark --starlark:expr="${staged_expr}" 2>/dev/null || true)"

  if [[ -n "${cquery_out}" ]]; then
    while IFS= read -r rel_path; do
      [[ -z "${rel_path}" ]] && continue
      if [[ "${rel_path}" == /* && -f "${rel_path}" ]]; then
        echo "${rel_path}" >> "${raw_list}"
      elif [[ -n "${exec_root}" && -f "${exec_root}/${rel_path}" ]]; then
        echo "${exec_root}/${rel_path}" >> "${raw_list}"
      elif [[ -f "${CREDENTIO_DIR}/${rel_path}" ]]; then
        echo "${CREDENTIO_DIR}/${rel_path}" >> "${raw_list}"
      elif [[ -n "${bazel_bin}" && -f "${bazel_bin}/${rel_path}" ]]; then
        echo "${bazel_bin}/${rel_path}" >> "${raw_list}"
      fi
    done <<< "${cquery_out}"
  fi

  if [[ -n "${bazel_bin}" && -d "${bazel_bin}" ]]; then
    find "${bazel_bin}" \( -name "*.a" -o -name "*.lo" \) -type f >> "${raw_list}" 2>/dev/null || true
  fi

  if [[ -f "${raw_list}" ]]; then
    sort -u "${raw_list}" | while IFS= read -r f; do
      [[ -n "$f" && -r "$f" ]] && echo "$f"
    done > "${archive_list}"
  fi

  local count
  count="$(wc -l < "${archive_list}" | tr -d ' ')"
  echo "==> Found ${count} static archive(s) for ${label}."
  if [[ "${count}" -eq 0 ]]; then
    echo "ERROR: Could not resolve static archives for ${label}." >&2
    return 1
  fi

  libtool -static -o "${out_file}" -filelist "${archive_list}"
  echo "${out_file}"
}

# 3. Build archives (attempt dual-arch arm64 + x86_64, falling back to host arch if needed)
BUILT_ARCHIVES=()

# Primary host build
echo "==> Building primary host architecture..."
if HOST_ARCHIVE="$(build_static_archive "host" "")"; then
  BUILT_ARCHIVES+=("${HOST_ARCHIVE}")
fi

# Attempt secondary architecture for universal binary if on macOS Apple Silicon
if [[ "$(uname -m)" == "arm64" && "${BUILD_UNIVERSAL:-1}" == "1" ]]; then
  echo "==> Attempting x86_64 cross-build for universal macOS binary..."
  if X86_ARCHIVE="$(build_static_archive "x86_64" "--cpu=darwin_x86_64" 2>/dev/null)"; then
    BUILT_ARCHIVES+=("${X86_ARCHIVE}")
  else
    echo "==> Note: x86_64 build not available in this environment; proceeding with arm64."
  fi
fi

FINAL_STATIC_LIB="${STAGE_DIR}/libCredentioC.a"
if [[ "${#BUILT_ARCHIVES[@]}" -gt 1 ]]; then
  echo "==> Creating universal binary with lipo (${#BUILT_ARCHIVES[@]} slices)..."
  lipo -create -output "${FINAL_STATIC_LIB}" "${BUILT_ARCHIVES[@]}"
else
  cp -f "${BUILT_ARCHIVES[0]}" "${FINAL_STATIC_LIB}"
fi

# 4. Package into XCFramework with xcodebuild
echo "==> Packaging into XCFramework at ${OUTPUT_XCFRAMEWORK}..."
rm -rf "${OUTPUT_XCFRAMEWORK}"
xcodebuild -create-xcframework \
  -library "${FINAL_STATIC_LIB}" \
  -headers "${HEADERS_DIR}" \
  -output "${OUTPUT_XCFRAMEWORK}"

echo "======================================================="
echo "SUCCESS: Created ${OUTPUT_XCFRAMEWORK}"
echo "======================================================="

# 5. Optional release zip and SwiftPM checksum
if [[ "${1:-}" == "--zip" || "${CREDENTIO_ZIP_RELEASE:-0}" == "1" ]]; then
  ZIP_PATH="${REPO_DIR}/swift/CredentioC.xcframework.zip"
  echo "==> Creating release archive at ${ZIP_PATH}..."
  rm -f "${ZIP_PATH}"
  (
    cd "${REPO_DIR}/swift"
    zip -q -r -y "CredentioC.xcframework.zip" "CredentioC.xcframework"
  )
  if command -v swift >/dev/null 2>&1; then
    CHECKSUM="$(swift package compute-checksum "${ZIP_PATH}")"
    echo "======================================================="
    echo "Release Archive:  swift/CredentioC.xcframework.zip"
    echo "SwiftPM Checksum: ${CHECKSUM}"
    echo "======================================================="
    echo "${CHECKSUM}" > "${REPO_DIR}/swift/CredentioC.xcframework.zip.sha256"
  fi
fi
