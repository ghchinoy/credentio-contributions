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
# build-wasm.sh: builds WebAssembly engine (credentio.wasm & credentio.js)
# from native/credentio_c.cc via Bazel + Emscripten toolchains.

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

DIRECT_BUILD=0
for arg in "$@"; do
  case "${arg}" in
    --direct|--in-container)
      DIRECT_BUILD=1
      ;;
    -h|--help)
      echo "Usage: ./scripts/build-wasm.sh [options]"
      echo ""
      echo "Options:"
      echo "  --direct       Build directly on host (requires bazel + em++ in PATH or EMSDK)"
      echo "  -h, --help     Show this help message"
      echo ""
      echo "Environment variables:"
      echo "  CREDENTIO_GIT_URL   Git repository URL (default: https://mediaprovenance.googlesource.com/credentio)"
      echo "  CREDENTIO_SHA       Git commit SHA to checkout (default: from .credentio-pin)"
      exit 0
      ;;
    *)
      echo "Unknown option: ${arg}" >&2
      echo "Run './scripts/build-wasm.sh --help' for usage." >&2
      exit 1
      ;;
  esac
done

echo "=== Building Google Credentio WebAssembly Engine ==="

# Function to execute direct Bazel compilation
run_direct_build() {
  local output_dir="$1"
  local work_dir
  work_dir="$(mktemp -d /tmp/credentio-wasm-build.XXXXXX)"
  trap 'rm -rf "${work_dir}"' EXIT

  echo "==> [Direct] Cloning Google Credentio (${CREDENTIO_SHA:0:7})..."
  git clone --depth 1 "${CREDENTIO_GIT_URL}" "${work_dir}/credentio"
  cd "${work_dir}/credentio"
  git checkout "${CREDENTIO_SHA}" 2>/dev/null || true

  echo "==> [Direct] Configuring emsdk Bazel toolchain..."
  echo 'bazel_dep(name = "emsdk", version = "6.0.8")' >> MODULE.bazel

  mkdir -p bindings_c
  cp "${REPO_DIR}/native/credentio_c.h" bindings_c/
  cp "${REPO_DIR}/native/credentio_c.cc" bindings_c/

  cat << 'BAZEL_EOF' > bindings_c/BUILD
load("@rules_cc//cc:defs.bzl", "cc_binary", "cc_library")

package(default_visibility = ["//visibility:public"])

cc_library(
    name = "credentio_c",
    srcs = ["credentio_c.cc"],
    hdrs = ["credentio_c.h"],
    copts = ["-std=c++20"],
    deps = [
        "//crypto:crypto_read_handler",
        "//crypto/default:default_crypto_read_handler",
        "//formats:core_registry",
        "//utils:crjson",
        "//utils:media_type",
        "//validator:asset_validator_impl",
        "//validator:result",
        "//validator:validator_options",
        "@abseil-cpp//absl/status",
        "@abseil-cpp//absl/status:statusor",
        "@abseil-cpp//absl/strings",
        "@nlohmann_json//:json",
        "@riegeli//riegeli/bytes:cfile_reader",
        "@riegeli//riegeli/bytes:string_reader",
    ],
    alwayslink = True,
)

cc_binary(
    name = "credentio.js",
    deps = [":credentio_c"],
    linkopts = [
        "-std=c++20",
        "-O3",
        "-sUSE_PTHREADS=0",
        "-sWASM=1",
        "-sALLOW_MEMORY_GROWTH=1",
        "-sMODULARIZE=1",
        "-sEXPORT_ES6=1",
        "-sEXPORT_NAME=createCredentioModule",
        "-sINITIAL_MEMORY=33554432",
        "-sSTACK_SIZE=5242880",
        "-sFORCE_FILESYSTEM=1",
        "-sENVIRONMENT=web,webview,worker,node",
        "-sEXPORTED_FUNCTIONS=['_cr_validator_create','_cr_validator_free','_cr_validate_file','_cr_validate_bytes','_cr_last_error','_cr_last_internal_seconds','_cr_string_free','_cr_version','_malloc','_free']",
        "-sEXPORTED_RUNTIME_METHODS=['ccall','cwrap','stringToUTF8','UTF8ToString','lengthBytesUTF8','getValue','setValue','FS','HEAPU8','HEAP8','HEAP32']",
    ],
)
BAZEL_EOF

  echo "==> [Direct] Compiling WebAssembly target via Bazel..."
  bazel build --platforms=@emsdk//:platform_wasm --cxxopt="-std=c++20" //bindings_c:credentio.js

  echo "==> [Direct] Extracting WebAssembly bundle..."
  mkdir -p "${work_dir}/unpacked"
  tar -xf bazel-bin/bindings_c/credentio.js -C "${work_dir}/unpacked"

  cp "${work_dir}/unpacked/credentio.js" "${output_dir}/credentio.js"
  cp "${work_dir}/unpacked/credentio.wasm" "${output_dir}/credentio.wasm"
  chmod 644 "${output_dir}"/credentio.*
}

STAGE_HOST_DIR="$(mktemp -d /tmp/credentio-wasm-stage.XXXXXX)"
trap 'rm -rf "${STAGE_HOST_DIR}"' EXIT

# Check if direct build was explicitly requested or if running in container / local emsdk
if [[ "${DIRECT_BUILD}" -eq 1 ]] || (command -v bazel >/dev/null 2>&1 && command -v em++ >/dev/null 2>&1); then
  echo "==> Detected direct Bazel & Emscripten toolchain in environment."
  run_direct_build "${STAGE_HOST_DIR}"
else
  # Containerized compilation detection
  CONTAINER_CLI=""
  if command -v container >/dev/null 2>&1; then
    CONTAINER_CLI="container"
  elif command -v docker >/dev/null 2>&1; then
    CONTAINER_CLI="docker"
  elif command -v podman >/dev/null 2>&1; then
    CONTAINER_CLI="podman"
  fi

  if [[ -z "${CONTAINER_CLI}" ]]; then
    echo "==========================================================================" >&2
    echo "ERROR: Neither Bazel+Emscripten nor a container runtime (Apple container / Docker / Podman) was found." >&2
    echo "To compile WebAssembly binaries, install Apple container or Docker/Podman." >&2
    echo "==========================================================================" >&2
    exit 1
  fi

  IMAGE_NAME="credentio-wasm-builder:latest"
  echo "==> Using container toolchain: ${CONTAINER_CLI} (Image: ${IMAGE_NAME})..."

  # Build container image if needed
  if ! "${CONTAINER_CLI}" image ls 2>/dev/null | grep -q "credentio-wasm-builder"; then
    echo "==> Building ${IMAGE_NAME}..."
    "${CONTAINER_CLI}" build -t "${IMAGE_NAME}" -f "${SCRIPT_DIR}/wasm/Containerfile" "${SCRIPT_DIR}/wasm"
  fi

  # Ensure persistent cache volume exists
  if ! "${CONTAINER_CLI}" volume ls 2>/dev/null | grep -q "credentio-bazel-cache"; then
    "${CONTAINER_CLI}" volume create credentio-bazel-cache >/dev/null 2>&1 || true
  fi

  echo "==> Executing WebAssembly Bazel build inside container..."
  "${CONTAINER_CLI}" run --rm \
    --cpus 8 \
    -m 16G \
    -v credentio-bazel-cache:/root/.cache \
    -v "${REPO_DIR}/native:/workspace/native:ro" \
    -v "${STAGE_HOST_DIR}:/workspace/output:rw" \
    -e CREDENTIO_GIT_URL="${CREDENTIO_GIT_URL}" \
    -e CREDENTIO_SHA="${CREDENTIO_SHA}" \
    "${IMAGE_NAME}" \
    /bin/bash -c "
      set -euo pipefail
      cd /tmp
      echo '==> [Container] Cloning Google Credentio (${CREDENTIO_SHA:0:7})...'
      git clone --depth 1 ${CREDENTIO_GIT_URL} credentio
      cd credentio

      echo '==> [Container] Configuring emsdk Bazel toolchain...'
      echo 'bazel_dep(name = \"emsdk\", version = \"6.0.8\")' >> MODULE.bazel

      mkdir -p bindings_c
      cp /workspace/native/credentio_c.h bindings_c/
      cp /workspace/native/credentio_c.cc bindings_c/

      cat << 'BAZEL_EOF' > bindings_c/BUILD
load(\"@rules_cc//cc:defs.bzl\", \"cc_binary\", \"cc_library\")

package(default_visibility = [\"//visibility:public\"])

cc_library(
    name = \"credentio_c\",
    srcs = [\"credentio_c.cc\"],
    hdrs = [\"credentio_c.h\"],
    copts = [\"-std=c++20\"],
    deps = [
        \"//crypto:crypto_read_handler\",
        \"//crypto/default:default_crypto_read_handler\",
        \"//formats:core_registry\",
        \"//utils:crjson\",
        \"//utils:media_type\",
        \"//validator:asset_validator_impl\",
        \"//validator:result\",
        \"//validator:validator_options\",
        \"@abseil-cpp//absl/status\",
        \"@abseil-cpp//absl/status:statusor\",
        \"@abseil-cpp//absl/strings\",
        \"@nlohmann_json//:json\",
        \"@riegeli//riegeli/bytes:cfile_reader\",
        \"@riegeli//riegeli/bytes:string_reader\",
    ],
    alwayslink = True,
)

cc_binary(
    name = \"credentio.js\",
    deps = [\":credentio_c\"],
    linkopts = [
        \"-std=c++20\",
        \"-O3\",
        \"-sUSE_PTHREADS=0\",
        \"-sWASM=1\",
        \"-sALLOW_MEMORY_GROWTH=1\",
        \"-sMODULARIZE=1\",
        \"-sEXPORT_ES6=1\",
        \"-sEXPORT_NAME=createCredentioModule\",
        \"-sINITIAL_MEMORY=33554432\",
        \"-sSTACK_SIZE=5242880\",
        \"-sFORCE_FILESYSTEM=1\",
        \"-sENVIRONMENT=web,webview,worker,node\",
        \"-sEXPORTED_FUNCTIONS=['_cr_validator_create','_cr_validator_free','_cr_validate_file','_cr_validate_bytes','_cr_last_error','_cr_last_internal_seconds','_cr_string_free','_cr_version','_malloc','_free']\",
        \"-sEXPORTED_RUNTIME_METHODS=['ccall','cwrap','stringToUTF8','UTF8ToString','lengthBytesUTF8','getValue','setValue','FS','HEAPU8','HEAP8','HEAP32']\",
    ],
)
BAZEL_EOF

      echo '==> [Container] Compiling WebAssembly target via Bazel...'
      bazel build --jobs=8 --disk_cache=/root/.cache/bazel_disk --repository_cache=/root/.cache/bazel_repo --platforms=@emsdk//:platform_wasm --cxxopt=\"-std=c++20\" //bindings_c:credentio.js

      echo '==> [Container] Extracting WebAssembly bundle...'
      mkdir -p /tmp/unpacked
      tar -xf bazel-bin/bindings_c/credentio.js -C /tmp/unpacked

      cp /tmp/unpacked/credentio.js /workspace/output/credentio.js
      cp /tmp/unpacked/credentio.wasm /workspace/output/credentio.wasm
      chmod 644 /workspace/output/credentio.*
    "
fi

# 2. Stage artifacts to target locations
WASM_DIST_DIR="${REPO_DIR}/wasm/dist"
WASM_LIB_DIR="${REPO_DIR}/wasm/lib"
DOCS_WASM_DIR="${REPO_DIR}/docs-site/public/wasm"

mkdir -p "${WASM_DIST_DIR}" "${WASM_LIB_DIR}" "${DOCS_WASM_DIR}"

rm -f "${WASM_DIST_DIR}/credentio.js" "${WASM_DIST_DIR}/credentio.wasm"
rm -f "${WASM_LIB_DIR}/credentio.js" "${WASM_LIB_DIR}/credentio.wasm"
rm -f "${DOCS_WASM_DIR}/credentio.js" "${DOCS_WASM_DIR}/credentio.wasm"

cp -f "${STAGE_HOST_DIR}/credentio.js" "${WASM_DIST_DIR}/credentio.js"
cp -f "${STAGE_HOST_DIR}/credentio.wasm" "${WASM_DIST_DIR}/credentio.wasm"

cp -f "${STAGE_HOST_DIR}/credentio.js" "${WASM_LIB_DIR}/credentio.js"
cp -f "${STAGE_HOST_DIR}/credentio.wasm" "${WASM_LIB_DIR}/credentio.wasm"

cp -f "${STAGE_HOST_DIR}/credentio.js" "${DOCS_WASM_DIR}/credentio.js"
cp -f "${STAGE_HOST_DIR}/credentio.wasm" "${DOCS_WASM_DIR}/credentio.wasm"

chmod 644 "${WASM_DIST_DIR}"/credentio.* "${WASM_LIB_DIR}"/credentio.* "${DOCS_WASM_DIR}"/credentio.*

echo "======================================================="
echo "SUCCESS: Staged WebAssembly engine into:"
echo "  - wasm/dist/credentio.{js,wasm}"
echo "  - wasm/lib/credentio.{js,wasm}"
echo "  - docs-site/public/wasm/credentio.{js,wasm}"
echo "======================================================="
