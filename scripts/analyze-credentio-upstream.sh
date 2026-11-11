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
# analyze-credentio-upstream.sh: Queries upstream Google Credentio (refs/heads/main
# and optional pending Gerrit CLs under refs/changes/*), inspects commit logs and
# file-level diffs via Gitiles JSON API, maps changes against the C-ABI surface
# (native/credentio_c.cc, native/BUILD, and 5-way ParseCrJSON parsers), and outputs
# an actionable upgrade/rebuild recommendation in text, Markdown, or JSON.
#
# Exit codes:
#   0 = In sync on refs/heads/main (or custom --target analysis succeeded)
#   1 = Drift detected on refs/heads/main (or pending CL found with --fail-on-pending)
#   2 = Network, dependency, or query error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

CREDENTIO_GIT_URL="${CREDENTIO_GIT_URL:-https://mediaprovenance.googlesource.com/credentio}"
PIN_FILE="${REPO_DIR}/.credentio-pin"

BASE_SHA="${CREDENTIO_BASE_SHA:-}"
TARGET_REF="${CREDENTIO_TARGET_REF:-refs/heads/main}"
EXPLICIT_TARGET=0
INCLUDE_PENDING=0
FAIL_ON_PENDING=0
OUTPUT_FORMAT="text"

usage() {
  cat <<'EOF'
Usage: ./scripts/analyze-credentio-upstream.sh [options]

Options:
  --base <sha>          Baseline commit SHA (default: from .credentio-pin)
  --target <sha|ref>    Target Git ref or commit SHA to analyze (default: refs/heads/main)
  --include-pending     Also discover and analyze open Gerrit CLs under refs/changes/*
  --fail-on-pending     Exit with code 1 if an open Gerrit CL is found even when main is in sync
  --json                Output structured JSON report to stdout
  --markdown            Output GitHub-flavored Markdown report to stdout
  -h, --help            Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      BASE_SHA="${2:-}"
      shift 2
      ;;
    --target)
      TARGET_REF="${2:-}"
      EXPLICIT_TARGET=1
      shift 2
      ;;
    --include-pending|--gerrit)
      INCLUDE_PENDING=1
      shift
      ;;
    --fail-on-pending)
      FAIL_ON_PENDING=1
      shift
      ;;
    --json)
      OUTPUT_FORMAT="json"
      shift
      ;;
    --markdown|--md)
      OUTPUT_FORMAT="markdown"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

for cmd in git curl jq; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: Required command '${cmd}' is not installed." >&2
    exit 2
  fi
done

if [[ -z "${BASE_SHA}" && -f "${PIN_FILE}" ]]; then
  BASE_SHA="$(tr -d '[:space:]' < "${PIN_FILE}")"
fi

if [[ -z "${BASE_SHA}" ]]; then
  echo "ERROR: Baseline SHA not found. Create .credentio-pin or pass --base <sha>." >&2
  exit 2
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/credentio-analyze.XXXXXX")"
trap 'rm -rf "${TMP_DIR}"' EXIT

# Helper: Fetch Gitiles JSON and strip the 5-byte XSSI guard ")]}'\n"
fetch_gitiles_json() {
  local path="$1"
  local url="${CREDENTIO_GIT_URL}/${path}"
  local raw_file="${TMP_DIR}/gitiles_raw.txt"
  if ! curl -fsSL "${url}" -o "${raw_file}" 2>/dev/null; then
    return 1
  fi
  tail -n +2 "${raw_file}"
}

# 1. Resolve upstream refs/heads/main SHA
MAIN_LS="$(git ls-remote "${CREDENTIO_GIT_URL}" refs/heads/main 2>/dev/null || true)"
if [[ -z "${MAIN_LS}" ]]; then
  echo "ERROR: Failed to query upstream remote at ${CREDENTIO_GIT_URL}." >&2
  exit 2
fi
UPSTREAM_MAIN_SHA="$(echo "${MAIN_LS}" | awk '{print $1}' | head -n 1)"

MAIN_STATUS="IN_SYNC"
if [[ "${BASE_SHA}" != "${UPSTREAM_MAIN_SHA}" ]]; then
  MAIN_STATUS="DRIFT_DETECTED"
fi

# 2. Resolve TARGET_SHA if custom --target was passed
TARGET_SHA="${UPSTREAM_MAIN_SHA}"
if [[ "${EXPLICIT_TARGET}" -eq 1 && "${TARGET_REF}" != "refs/heads/main" ]]; then
  if [[ "${TARGET_REF}" =~ ^[0-9a-f]{40}$ ]]; then
    TARGET_SHA="${TARGET_REF}"
  elif [[ "${TARGET_REF}" =~ ^refs/ ]]; then
    RESOLVED_LS="$(git ls-remote "${CREDENTIO_GIT_URL}" "${TARGET_REF}" 2>/dev/null || true)"
    if [[ -z "${RESOLVED_LS}" ]]; then
      echo "ERROR: Could not resolve target ref '${TARGET_REF}' on ${CREDENTIO_GIT_URL}." >&2
      exit 2
    fi
    TARGET_SHA="$(echo "${RESOLVED_LS}" | awk '{print $1}' | head -n 1)"
  else
    # Short SHA or branch/tag ref: query Gitiles commit JSON
    COMMIT_JSON="$(fetch_gitiles_json "+/${TARGET_REF}?format=JSON" || true)"
    if [[ -z "${COMMIT_JSON}" ]]; then
      echo "ERROR: Could not resolve target '${TARGET_REF}' via Gitiles." >&2
      exit 2
    fi
    TARGET_SHA="$(echo "${COMMIT_JSON}" | jq -r '.commit // empty')"
    if [[ -z "${TARGET_SHA}" ]]; then
      echo "ERROR: Invalid commit response for target '${TARGET_REF}'." >&2
      exit 2
    fi
  fi
fi

# 3. Discover pending Gerrit CLs under refs/changes/* if requested
PENDING_CLS_JSON="[]"
if [[ "${INCLUDE_PENDING}" -eq 1 ]]; then
  CHANGES_FILE="${TMP_DIR}/changes_ls.txt"
  git ls-remote "${CREDENTIO_GIT_URL}" 'refs/changes/*' > "${CHANGES_FILE}" 2>/dev/null || true

  # Find the CL number corresponding to UPSTREAM_MAIN_SHA (if any) so we only inspect newer CLs
  BASELINE_CL_NUM="$(awk -v sha="${UPSTREAM_MAIN_SHA}" '$1 == sha && $2 ~ /^refs\/changes\/[0-9]+\/[0-9]+\/[0-9]+$/ { split($2, a, "/"); print a[4] }' "${CHANGES_FILE}" | sort -n | tail -n 1)"
  BASELINE_CL_NUM="${BASELINE_CL_NUM:-0}"

  # Extract highest numeric patchset per CL for CL numbers > BASELINE_CL_NUM
  CANDIDATE_CLS="$(awk -F'/' -v min_cl="${BASELINE_CL_NUM}" '
    $0 ~ /\trefs\/changes\/[0-9]+\/[0-9]+\/[0-9]+$/ {
      split($1, f, "\t")
      sha = f[1]
      shard = $3
      cl = $4 + 0
      ps = $5 + 0
      if (cl > min_cl) {
        if (ps > max_ps[cl]) {
          max_ps[cl] = ps
          best_sha[cl] = sha
          best_shard[cl] = shard
        }
      }
    }
    END {
      for (cl in max_ps) {
        printf "%d\t%d\t%s\trefs/changes/%s/%d/%d\n", cl, max_ps[cl], best_sha[cl], best_shard[cl], cl, max_ps[cl]
      }
    }
  ' "${CHANGES_FILE}" | sort -n)"

  PENDING_ITEMS=()
  while IFS=$'\t' read -r cl_num ps_num cl_sha cl_ref; do
    [[ -z "${cl_num}" ]] && continue
    shard_num="$(echo "${cl_ref}" | awk -F'/' '{print $3}')"
    meta_ref="refs/changes/${shard_num}/${cl_num}/meta"
    meta_sha="$(awk -v ref="${meta_ref}" '$2 == ref {print $1; exit}' "${CHANGES_FILE}")"

    # Check NoteDb /meta commit message for Status: merged or Status: abandoned
    if [[ -n "${meta_sha}" ]]; then
      meta_json="$(fetch_gitiles_json "+/${meta_sha}?format=JSON" || true)"
      meta_msg="$(echo "${meta_json}" | jq -r '.message // ""' 2>/dev/null || true)"
      if echo "${meta_msg}" | grep -qiE '^Status:\s*(merged|abandoned)'; then
        continue
      fi
    fi

    # Fetch commit details from Gitiles and verify it parents onto UPSTREAM_MAIN_SHA (or BASE_SHA)
    cl_json="$(fetch_gitiles_json "+/${cl_sha}?format=JSON" || true)"
    [[ -z "${cl_json}" ]] && continue

    parent_sha="$(echo "${cl_json}" | jq -r '.parents[0] // ""')"
    if [[ "${parent_sha}" != "${UPSTREAM_MAIN_SHA}" && "${parent_sha}" != "${BASE_SHA}" ]]; then
      # Skip non-main CLs (such as refs/meta/config Gerrit ACL changes)
      continue
    fi

    cl_subject="$(echo "${cl_json}" | jq -r '(.message // "" | split("\n")[0])')"
    cl_date="$(echo "${cl_json}" | jq -r '.committer.time // ""')"
    cl_item="$(jq -n \
      --arg change_id "${cl_num}" \
      --argjson patchset "${ps_num}" \
      --arg ref "${cl_ref}" \
      --arg sha "${cl_sha}" \
      --arg short_sha "${cl_sha:0:7}" \
      --arg parent_sha "${parent_sha}" \
      --arg subject "${cl_subject}" \
      --arg date "${cl_date}" \
      --arg url "${CREDENTIO_GIT_URL}/+/${cl_sha}" \
      '{change_id: $change_id, patchset: $patchset, ref: $ref, sha: $sha, short_sha: $short_sha, parent_sha: $parent_sha, subject: $subject, date: $date, url: $url}')"
    PENDING_ITEMS+=("${cl_item}")
  done <<< "${CANDIDATE_CLS}"

  if [[ "${#PENDING_ITEMS[@]}" -gt 0 ]]; then
    PENDING_CLS_JSON="$(printf '%s\n' "${PENDING_ITEMS[@]}" | jq -s '.')"
  fi
fi

# 4. Determine which target SHA to run deep diff analysis on:
#    - If explicit --target was passed: analyze BASE_SHA..TARGET_SHA
#    - Else if main has drifted: analyze BASE_SHA..UPSTREAM_MAIN_SHA
#    - Else if --include-pending found an open CL on top of main: analyze BASE_SHA..<latest_pending_cl_sha>
ANALYZED_SHA="${TARGET_SHA}"
ANALYZED_REF="${TARGET_REF}"
ANALYZED_IS_PENDING=0

if [[ "${EXPLICIT_TARGET}" -eq 0 && "${MAIN_STATUS}" == "IN_SYNC" && "${INCLUDE_PENDING}" -eq 1 ]]; then
  LATEST_PENDING_SHA="$(echo "${PENDING_CLS_JSON}" | jq -r '.[-1].sha // empty')"
  LATEST_PENDING_REF="$(echo "${PENDING_CLS_JSON}" | jq -r '.[-1].ref // empty')"
  if [[ -n "${LATEST_PENDING_SHA}" ]]; then
    ANALYZED_SHA="${LATEST_PENDING_SHA}"
    ANALYZED_REF="${LATEST_PENDING_REF}"
    ANALYZED_IS_PENDING=1
  fi
fi

# 5. Fetch commit log and aggregate file-level diffs for BASE_SHA..ANALYZED_SHA
COMMITS_JSON="[]"
CHANGED_FILES_JSON="[]"
COMMITS_AHEAD=0

if [[ "${BASE_SHA}" != "${ANALYZED_SHA}" ]]; then
  LOG_JSON="$(fetch_gitiles_json "+log/${BASE_SHA}..${ANALYZED_SHA}?format=JSON" || true)"
  if [[ -n "${LOG_JSON}" ]]; then
    COMMITS_JSON="$(echo "${LOG_JSON}" | jq '[.log[]? | {
      sha: .commit,
      short_sha: (.commit[0:7]),
      subject: (.message | split("\n")[0]),
      message: .message,
      author: (.author.name // ""),
      date: (.committer.time // "")
    }]')"
    COMMITS_AHEAD="$(echo "${COMMITS_JSON}" | jq 'length')"
  fi

  # Collect tree_diff across commits in range (capped at 20 commits to respect rate limits)
  DIFF_ACCUM_FILE="${TMP_DIR}/diff_accum.jsonl"
  touch "${DIFF_ACCUM_FILE}"

  COMMIT_SHAS="$(echo "${COMMITS_JSON}" | jq -r '.[0:20][].sha')"
  if [[ -z "${COMMIT_SHAS}" ]]; then
    COMMIT_SHAS="${ANALYZED_SHA}"
  fi

  while IFS= read -r c_sha; do
    [[ -z "${c_sha}" ]] && continue
    c_detail="$(fetch_gitiles_json "+/${c_sha}?format=JSON" || true)"
    [[ -z "${c_detail}" ]] && continue
    echo "${c_detail}" | jq -c '.tree_diff[]? | {
      status: .type,
      path: (if .type == "delete" then .old_path else .new_path end)
    }' >> "${DIFF_ACCUM_FILE}"
  done <<< "${COMMIT_SHAS}"

  # Classify each unique changed file against native/credentio_c.cc and ParseCrJSON dependencies
  CHANGED_FILES_JSON="$(jq -s '
    group_by(.path) | map(last) | map(
      .path as $p |
      if (
        $p == "claim/local_signer.h" or
        $p == "crypto/crypto_read_handler.h" or
        $p == "crypto/crypto_write_handler.h" or
        $p == "crypto/hash.h" or
        $p == "crypto/templated_crypto_write_handler.h" or
        $p == "crypto/default/default_crypto_read_handler.h" or
        $p == "crypto/default/hasher.h" or
        $p == "crypto/default/pem.h" or
        $p == "formats/bmff/writer.h" or
        $p == "formats/gif/writer.h" or
        $p == "formats/id3/writer.h" or
        $p == "formats/jpeg/writer.h" or
        $p == "formats/pdf/writer.h" or
        $p == "formats/png/writer.h" or
        $p == "formats/riff/writer.h" or
        $p == "formats/tiff/writer.h" or
        $p == "formats/zip/writer.h" or
        $p == "generator/generator.h" or
        $p == "generator/generator_factory.h" or
        $p == "generator/generator_options.h" or
        $p == "testing/local_key_crypto_write_handler.h" or
        $p == "testing/local_key_crypto_write_handler.cc" or
        $p == "utils/crjson.h" or
        $p == "utils/media_type.h" or
        $p == "validator/asset_validator_impl.h" or
        $p == "validator/result.h" or
        $p == "validator/validator_options.h"
      ) then
        . + {category: "direct_c_abi_header", impact_level: "high", reason: "Directly included or linked by native/credentio_c.cc"}
      elif (
        $p == "utils/crjson.cc" or
        $p == "utils/media_type.cc" or
        $p == "constants/spec_version.h" or
        ($p | startswith("proto/"))
      ) then
        . + {category: "schema_or_crjson", impact_level: "high", reason: "Affects crJSON output schema, SpecVersion, or generator protobufs"}
      elif (
        $p == "MODULE.bazel" or
        $p == "WORKSPACE" or
        $p == ".bazelrc" or
        ($p | endswith("/BUILD")) or
        $p == "BUILD"
      ) then
        . + {category: "build_graph", impact_level: "medium", reason: "Bazel dependency or target graph change"}
      elif (
        ($p | endswith("_test.cc")) or
        ($p | endswith("_test.h")) or
        ($p | startswith("testing/")) or
        ($p | startswith("kokoro/")) or
        ($p | startswith("tracing/")) or
        ($p | startswith("docs/")) or
        ($p | startswith("README"))
      ) then
        . + {category: "tests_or_internal", impact_level: "low", reason: "Test, tracing, or CI configuration"}
      else
        . + {category: "core_or_formats", impact_level: "medium", reason: "Core validation, signing, cryptography, or media format implementation"}
      end
    )
  ' "${DIFF_ACCUM_FILE}")"
fi

# 6. Compute summary & recommendation tier
SUMMARY_JSON="$(jq -n \
  --arg repository "${CREDENTIO_GIT_URL}" \
  --arg pinned_sha "${BASE_SHA}" \
  --arg upstream_main_sha "${UPSTREAM_MAIN_SHA}" \
  --arg main_status "${MAIN_STATUS}" \
  --arg analyzed_ref "${ANALYZED_REF}" \
  --arg analyzed_sha "${ANALYZED_SHA}" \
  --argjson analyzed_is_pending "${ANALYZED_IS_PENDING}" \
  --argjson commits_ahead "${COMMITS_AHEAD}" \
  --argjson commits "${COMMITS_JSON}" \
  --argjson changed_files "${CHANGED_FILES_JSON}" \
  --argjson pending_gerrit_cls "${PENDING_CLS_JSON}" \
  '
  ($changed_files | map(select(.category == "direct_c_abi_header")) | map(.path)) as $direct_headers |
  ($changed_files | map(select(.category == "schema_or_crjson")) | map(.path)) as $schema_files |
  ($changed_files | map(select(.category == "build_graph")) | map(.path)) as $build_files |
  ($changed_files | map(select(.category == "core_or_formats")) | map(.path)) as $core_files |
  ($changed_files | map(select(.category == "tests_or_internal")) | map(.path)) as $test_files |
  (
    if ($pinned_sha == $analyzed_sha) then "NONE"
    elif (($direct_headers | length) > 0 or ($schema_files | length) > 0) then "ABI_REVIEW_REQUIRED"
    elif (($core_files | length) > 0 or ($build_files | length) > 0) then "REBUILD_RECOMMENDED"
    else "SKIP_LOW"
    end
  ) as $tier |
  (
    if $tier == "NONE" then
      "Upstream is in sync with .credentio-pin and no pending release CLs were detected. No action needed."
    elif ($analyzed_is_pending == 1) then
      "Upstream main is currently in sync, but an open Gerrit release CL (" + ($analyzed_sha[0:7]) + ") is staged with " + ($core_files | length | tostring) + " core/format changes and " + (($direct_headers | length) + ($schema_files | length) | tostring) + " C-ABI/schema changes. Pre-test now and rebuild/republish once merged to main."
    elif $tier == "ABI_REVIEW_REQUIRED" then
      "Upstream modified C-ABI headers, crJSON/SpecVersion, or protobuf schemas. Run full build + 4-language test suites and verify 5-way ParseCrJSON compatibility before bumping .credentio-pin and cutting a release."
    elif $tier == "REBUILD_RECOMMENDED" then
      "Upstream modified core validation, cryptography, or media format implementations without direct C-ABI header changes. Rebuild native binaries, verify all 4 test suites, bump .credentio-pin, and publish a patch/minor release."
    else
      "Only tests, tracing, or CI files changed upstream. Rebuilding/republishing libraries is optional."
    end
  ) as $recommendation_text |
  {
    repository: $repository,
    pinned_sha: $pinned_sha,
    upstream_main_sha: $upstream_main_sha,
    main_status: $main_status,
    analyzed_ref: $analyzed_ref,
    analyzed_sha: $analyzed_sha,
    analyzed_is_pending_cl: ($analyzed_is_pending == 1),
    compare_url: (if $pinned_sha != $analyzed_sha then ($repository + "/+log/" + $pinned_sha + ".." + $analyzed_sha) else null end),
    commits_ahead: $commits_ahead,
    recommendation_tier: $tier,
    recommendation_summary: $recommendation_text,
    impact_summary: {
      total_files_changed: ($changed_files | length),
      direct_c_abi_headers: $direct_headers,
      schema_or_crjson_files: $schema_files,
      build_graph_files: $build_files,
      core_or_format_files: $core_files,
      tests_or_internal_files: $test_files
    },
    pending_gerrit_cls: $pending_gerrit_cls,
    commits: $commits,
    changed_files: $changed_files
  }
  ')"

# 7. Render output in requested format
if [[ "${OUTPUT_FORMAT}" == "json" ]]; then
  echo "${SUMMARY_JSON}" | jq .
elif [[ "${OUTPUT_FORMAT}" == "markdown" ]]; then
  echo "${SUMMARY_JSON}" | jq -r '
    "## Upstream Credentio Drift & Impact Analysis\n\n" +
    "| Field | Value |\n" +
    "| :--- | :--- |\n" +
    "| **Pinned Commit (`.credentio-pin`)** | `" + .pinned_sha + "` |\n" +
    "| **Upstream `refs/heads/main`** | `" + .upstream_main_sha + "` (**" + .main_status + "**) |\n" +
    "| **Analyzed Target** | `" + .analyzed_ref + "` (`" + (.analyzed_sha[0:7]) + "`)" + (if .analyzed_is_pending_cl then " *(Pending Gerrit CL)*" else "" end) + " |\n" +
    "| **Recommendation Tier** | **`" + .recommendation_tier + "`** |\n" +
    (if .compare_url then "| **Compare Log** | [" + (.pinned_sha[0:7]) + ".." + (.analyzed_sha[0:7]) + "](" + .compare_url + ") |\n" else "" end) +
    "\n### Recommendation\n\n> " + .recommendation_summary + "\n" +
    (if (.pending_gerrit_cls | length) > 0 then
      "\n### Open Gerrit Release CLs (`refs/changes/*`)\n\n" +
      (.pending_gerrit_cls | map("- **CL " + .change_id + " (PS " + (.patchset | tostring) + ")**: [`" + .short_sha + "`](" + .url + ") (`" + .ref + "`) - " + .subject + " *(" + .date + ")*") | join("\n")) + "\n"
    else "" end) +
    (if (.changed_files | length) > 0 then
      "\n### Impact Breakdown (" + (.impact_summary.total_files_changed | tostring) + " files touched)\n\n" +
      "- **Direct C-ABI Headers (`native/credentio_c.cc`):** " + (.impact_summary.direct_c_abi_headers | length | tostring) +
        (if (.impact_summary.direct_c_abi_headers | length) > 0 then " (`" + (.impact_summary.direct_c_abi_headers | join("`, `")) + "`)" else "" end) + "\n" +
      "- **Schema / `crJSON` / `SpecVersion` / Protobuf:** " + (.impact_summary.schema_or_crjson_files | length | tostring) +
        (if (.impact_summary.schema_or_crjson_files | length) > 0 then " (`" + (.impact_summary.schema_or_crjson_files | join("`, `")) + "`)" else "" end) + "\n" +
      "- **Bazel `BUILD` / `MODULE.bazel` Files:** " + (.impact_summary.build_graph_files | length | tostring) +
        (if (.impact_summary.build_graph_files | length) > 0 then " (`" + (.impact_summary.build_graph_files | join("`, `")) + "`)" else "" end) + "\n" +
      "- **Core Validation, Crypto & Media Formats:** " + (.impact_summary.core_or_format_files | length | tostring) + "\n" +
      "- **Tests, Tracing & CI Only:** " + (.impact_summary.tests_or_internal_files | length | tostring) + "\n" +
      "\n### Upstream Commit Highlights\n\n" +
      (.commits | map("#### `" + .short_sha + "` (" + .date + ")\n```text\n" + (.message | rtrimstr("\n")) + "\n```") | join("\n\n"))
    else "" end)
  '
else
  echo "${SUMMARY_JSON}" | jq -r '
    "=== Google Credentio Upstream Drift & Impact Analysis ===\n" +
    "Repository:          " + .repository + "\n" +
    "Pinned (.credentio): " + .pinned_sha + "\n" +
    "Upstream main:       " + .upstream_main_sha + " (" + .main_status + ")\n" +
    "Analyzed Target:     " + .analyzed_ref + " (" + (.analyzed_sha[0:12]) + ")" + (if .analyzed_is_pending_cl then " [Pending Gerrit CL]" else "" end) + "\n" +
    "Recommendation Tier: " + .recommendation_tier + "\n" +
    "=========================================================\n\n" +
    "Summary:\n  " + .recommendation_summary + "\n" +
    (if (.pending_gerrit_cls | length) > 0 then
      "\nOpen Gerrit Release CLs:\n" +
      (.pending_gerrit_cls | map("  - CL " + .change_id + " (patchset " + (.patchset | tostring) + "): " + .short_sha + " [" + .ref + "] " + .subject + " (" + .date + ")") | join("\n")) + "\n"
    else "" end) +
    (if (.changed_files | length) > 0 then
      "\nSubsystem Impact (" + (.impact_summary.total_files_changed | tostring) + " files changed):\n" +
      "  - Direct C-ABI Headers:      " + (.impact_summary.direct_c_abi_headers | length | tostring) +
        (if (.impact_summary.direct_c_abi_headers | length) > 0 then " (" + (.impact_summary.direct_c_abi_headers | join(", ")) + ")" else "" end) + "\n" +
      "  - Schema / crJSON / Proto:   " + (.impact_summary.schema_or_crjson_files | length | tostring) +
        (if (.impact_summary.schema_or_crjson_files | length) > 0 then " (" + (.impact_summary.schema_or_crjson_files | join(", ")) + ")" else "" end) + "\n" +
      "  - Bazel BUILD / MODULE:      " + (.impact_summary.build_graph_files | length | tostring) + "\n" +
      "  - Core / Crypto / Formats:   " + (.impact_summary.core_or_format_files | length | tostring) + "\n" +
      "  - Tests / Tracing / CI:      " + (.impact_summary.tests_or_internal_files | length | tostring) + "\n" +
      "\nPre-Test Commands (for " + (.analyzed_sha[0:7]) + "):\n" +
      "  export CREDENTIO_SHA=\"" + .analyzed_sha + "\"\n" +
      "  make build-lib && make python-test && make go-test\n" +
      "  make build-swift && make swift-test\n" +
      "  make build-wasm && make wasm-test\n"
    else "" end)
  '
fi

# 8. Exit code determination
if [[ "${MAIN_STATUS}" == "DRIFT_DETECTED" ]]; then
  exit 1
fi
if [[ "${FAIL_ON_PENDING}" -eq 1 && "${ANALYZED_IS_PENDING}" -eq 1 ]]; then
  exit 1
fi
exit 0
