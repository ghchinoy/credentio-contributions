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
# check-credentio-drift.sh: verifies whether upstream Google Credentio main
# has drifted from the commit pinned in .credentio-pin.
#
# Exit codes:
#   0 = In sync (no drift)
#   1 = Drift detected (upstream has new commits)
#   2 = Error querying upstream repository

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CREDENTIO_GIT_URL="${CREDENTIO_GIT_URL:-https://mediaprovenance.googlesource.com/credentio}"
PIN_FILE="${REPO_DIR}/.credentio-pin"

# 1. Resolve canonical pinned SHA
PINNED_SHA="${CREDENTIO_SHA:-}"
if [[ -z "${PINNED_SHA}" && -f "${PIN_FILE}" ]]; then
  PINNED_SHA="$(tr -d '[:space:]' < "${PIN_FILE}")"
fi

if [[ -z "${PINNED_SHA}" ]]; then
  echo "ERROR: Pinned SHA not found. Create .credentio-pin or set CREDENTIO_SHA." >&2
  exit 2
fi

echo "=== Checking Google Credentio Upstream Drift ==="
echo "Repository: ${CREDENTIO_GIT_URL}"
echo "Pinned SHA: ${PINNED_SHA}"

# 2. Query upstream HEAD / main branch commit
UPSTREAM_OUTPUT="$(git ls-remote "${CREDENTIO_GIT_URL}" refs/heads/main 2>/dev/null || true)"
if [[ -z "${UPSTREAM_OUTPUT}" ]]; then
  UPSTREAM_OUTPUT="$(git ls-remote "${CREDENTIO_GIT_URL}" HEAD 2>/dev/null || true)"
fi

if [[ -z "${UPSTREAM_OUTPUT}" ]]; then
  echo "ERROR: Failed to query upstream remote at ${CREDENTIO_GIT_URL} (network or remote error)." >&2
  exit 2
fi

UPSTREAM_SHA="$(echo "${UPSTREAM_OUTPUT}" | awk '{print $1}' | head -n 1)"
echo "Upstream:   ${UPSTREAM_SHA}"
echo "================================================"

# 3. Compare pinned SHA vs upstream SHA
if [[ "${PINNED_SHA}" == "${UPSTREAM_SHA}" ]]; then
  echo "STATUS: IN_SYNC"
  echo "Google Credentio is in sync with pinned commit (${PINNED_SHA:0:7})."
  exit 0
else
  echo "STATUS: DRIFT_DETECTED"
  echo "Upstream Credentio main branch has advanced."
  echo ""
  echo "  Pinned:   ${PINNED_SHA}"
  echo "  Upstream: ${UPSTREAM_SHA}"
  echo "  Compare:  https://mediaprovenance.googlesource.com/credentio/+log/${PINNED_SHA}..${UPSTREAM_SHA}"
  echo ""
  echo "To update the pin after testing:"
  echo "  echo \"${UPSTREAM_SHA}\" > .credentio-pin"
  exit 1
fi
